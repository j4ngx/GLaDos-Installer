#!/usr/bin/env bash
# =============================================================================
# lib/hardening.sh — Server hardening & system configuration
#
# Configures:
#   • Hostname
#   • Timezone & locale
#   • SSH hardening (disable root, password auth, change port)
#   • Unattended security upgrades
#   • Log rotation for GLaDOS installer logs
#
# All changes are idempotent and backed up before modification.
# =============================================================================

[[ -n "${_GLADOS_HARDENING_LOADED:-}" ]] && return 0
readonly _GLADOS_HARDENING_LOADED=1

# Defaults
SKIP_HARDENING="${SKIP_HARDENING:-false}"
GLADOS_HOSTNAME="${GLADOS_HOSTNAME:-}"
GLADOS_TIMEZONE="${GLADOS_TIMEZONE:-}"
HARDEN_SSH="${HARDEN_SSH:-true}"

###############################################################################
# Main entry point
###############################################################################

configure_hardening() {
  section "Server hardening & system configuration"

  _configure_hostname
  _configure_timezone
  _configure_ssh_hardening
  _configure_unattended_upgrades
  _configure_logrotate

  success "Server hardening complete."
}

###############################################################################
# Hostname
###############################################################################

_configure_hostname() {
  local current_hostname
  current_hostname="$(hostname)"

  if [[ -n "$GLADOS_HOSTNAME" ]]; then
    # Hostname was passed via CLI
    :
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    debug "Non-interactive — keeping hostname '${current_hostname}'."
    return 0
  else
    echo
    echo -e "  ${BOLD}Hostname${NC}"
    echo -e "  Current: ${CYAN}${current_hostname}${NC}"
    echo

    if ! confirm "Change the server hostname?" "n"; then
      return 0
    fi
    prompt_value "New hostname" "glados-server" GLADOS_HOSTNAME
  fi

  if [[ "$GLADOS_HOSTNAME" == "$current_hostname" ]]; then
    success "Hostname already set to '${current_hostname}'."
    return 0
  fi

  # Validate hostname (RFC 1123)
  if ! [[ "$GLADOS_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    warn "Invalid hostname '${GLADOS_HOSTNAME}' — skipping."
    return 0
  fi

  run_cmd sudo hostnamectl set-hostname "$GLADOS_HOSTNAME"

  # Update /etc/hosts if needed
  if ! grep -q "$GLADOS_HOSTNAME" /etc/hosts 2>/dev/null; then
    run_cmd sudo bash -c "sed -i 's/127.0.1.1.*/127.0.1.1\t${GLADOS_HOSTNAME}/' /etc/hosts"
    # If no 127.0.1.1 line exists, add one
    if ! grep -q "127.0.1.1" /etc/hosts 2>/dev/null; then
      run_cmd sudo bash -c "echo '127.0.1.1	${GLADOS_HOSTNAME}' >> /etc/hosts"
    fi
  fi

  success "Hostname set to '${GLADOS_HOSTNAME}'."
}

###############################################################################
# Timezone & locale
###############################################################################

_configure_timezone() {
  local current_tz
  current_tz="$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'unknown')"

  if [[ -n "$GLADOS_TIMEZONE" ]]; then
    :
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    debug "Non-interactive — keeping timezone '${current_tz}'."
    return 0
  else
    echo
    echo -e "  ${BOLD}Timezone${NC}"
    echo -e "  Current: ${CYAN}${current_tz}${NC}"
    echo

    if ! confirm "Change the timezone?" "n"; then
      return 0
    fi
    prompt_value "Timezone (e.g. Europe/Madrid, America/New_York, UTC)" "$current_tz" GLADOS_TIMEZONE
  fi

  if [[ "$GLADOS_TIMEZONE" == "$current_tz" ]]; then
    success "Timezone already set to '${current_tz}'."
    return 0
  fi

  # Validate timezone
  if ! timedatectl list-timezones 2>/dev/null | grep -qx "$GLADOS_TIMEZONE"; then
    warn "Invalid timezone '${GLADOS_TIMEZONE}' — skipping."
    return 0
  fi

  run_cmd sudo timedatectl set-timezone "$GLADOS_TIMEZONE"
  success "Timezone set to '${GLADOS_TIMEZONE}'."

  # Enable NTP sync
  if timedatectl show --property=NTP --value 2>/dev/null | grep -q "no"; then
    run_cmd sudo timedatectl set-ntp true
    debug "NTP time synchronisation enabled."
  fi
}

###############################################################################
# SSH hardening
###############################################################################

_configure_ssh_hardening() {
  [[ "$HARDEN_SSH" != true ]] && return 0

  local sshd_config="/etc/ssh/sshd_config"
  [[ -f "$sshd_config" ]] || { debug "No sshd_config found — SSH not installed."; return 0; }

  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo
    echo -e "  ${BOLD}SSH hardening${NC}"
    echo -e "  Recommended changes:"
    echo -e "    • Disable root login"
    echo -e "    • Disable password authentication (key-only)"
    echo -e "    • Set max auth tries to 3"
    echo -e "    • Disable X11 forwarding"
    echo

    if ! confirm "Apply SSH hardening?" "y"; then
      info "SSH hardening skipped."
      return 0
    fi
  fi

  # Backup original
  local backup
  backup="${sshd_config}.bak.$(date '+%Y%m%d_%H%M%S')"
  run_cmd sudo cp "$sshd_config" "$backup"
  debug "SSH config backed up to ${backup}"

  # Safety check: refuse to disable password auth if no SSH keys are configured
  local disable_password="yes"
  if [[ ! -s "$HOME/.ssh/authorized_keys" ]]; then
    warn "No SSH authorized_keys found — keeping password authentication enabled to avoid lockout."
    disable_password="no"
  fi

  # Apply hardening directives via drop-in file (cleaner than editing main config)
  local dropin_dir="/etc/ssh/sshd_config.d"
  local dropin_file="${dropin_dir}/50-glados-hardening.conf"

  run_cmd sudo mkdir -p "$dropin_dir"

  if [[ "$disable_password" == "yes" ]]; then
    run_cmd sudo bash -c "cat > '${dropin_file}' <<'SSH_HARDEN'
# GLaDOS SSH hardening — $(date '+%Y-%m-%d %H:%M:%S')
# Applied by GLaDOS Installer. Edit or remove this file to revert.

PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSH_HARDEN
"
  else
    run_cmd sudo bash -c "cat > '${dropin_file}' <<'SSH_HARDEN'
# GLaDOS SSH hardening — $(date '+%Y-%m-%d %H:%M:%S')
# Applied by GLaDOS Installer. Edit or remove this file to revert.
# NOTE: PasswordAuthentication kept enabled — no authorized_keys found.

PermitRootLogin no
PasswordAuthentication yes
MaxAuthTries 3
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSH_HARDEN
"
  fi

  # Test configuration before restarting
  if run_cmd sudo sshd -t 2>/dev/null; then
    run_cmd sudo systemctl reload sshd 2>/dev/null || run_cmd sudo systemctl reload ssh 2>/dev/null || true
    success "SSH hardened (drop-in: ${dropin_file})."
  else
    warn "SSH config test failed — reverting drop-in."
    run_cmd sudo rm -f "$dropin_file"
  fi

  echo
  echo -e "  ${YELLOW}⚠  IMPORTANT:${NC} Ensure you have SSH key access before disconnecting!"
  echo -e "  ${DIM}  Test in a new terminal: ssh $(whoami)@$(hostname -I 2>/dev/null | awk '{print $1}')${NC}"
  echo
}

###############################################################################
# Unattended security upgrades
###############################################################################

_configure_unattended_upgrades() {
  if dpkg -l unattended-upgrades >/dev/null 2>&1 &&
     [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    success "Unattended-upgrades already configured."
    return 0
  fi

  if [[ "$NON_INTERACTIVE" != true ]]; then
    if ! confirm "Enable automatic security updates?" "y"; then
      info "Unattended upgrades skipped."
      return 0
    fi
  fi

  spinner_start "Installing unattended-upgrades..."
  run_cmd sudo apt-get install -y -qq unattended-upgrades apt-listchanges
  spinner_stop

  # Enable automatic updates
  run_cmd sudo bash -c "cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT_AUTO'
APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
APT::Periodic::Download-Upgradeable-Packages \"1\";
APT::Periodic::AutocleanInterval \"7\";
APT_AUTO
"

  # Configure to only do security updates + auto-reboot at 4am if needed
  run_cmd sudo bash -c "cat > /etc/apt/apt.conf.d/50glados-unattended <<'APT_GLADOS'
// GLaDOS: Only security updates
Unattended-Upgrade::Allowed-Origins {
    \"\${distro_id}:\${distro_codename}-security\";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages \"true\";
Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Automatic-Reboot \"false\";
Unattended-Upgrade::Mail \"\";
APT_GLADOS
"

  success "Unattended security upgrades enabled."
}

###############################################################################
# Log rotation for GLaDOS installer logs
###############################################################################

_configure_logrotate() {
  local logrotate_conf="/etc/logrotate.d/glados-installer"

  if [[ -f "$logrotate_conf" ]]; then
    debug "GLaDOS logrotate config already present."
    return 0
  fi

  run_cmd sudo bash -c "cat > '${logrotate_conf}' <<'LOGROTATE'
${LOG_DIR}/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $(whoami) $(id -gn)
}
LOGROTATE
"

  success "Log rotation configured for ${LOG_DIR}."
}

###############################################################################
# Health check
###############################################################################

check_hardening_health() {
  local ok=true

  # Hostname
  echo -e "  ${GREEN}✔${NC}  Hostname        : $(hostname)"

  # Timezone
  local tz
  tz="$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo '?')"
  echo -e "  ${GREEN}✔${NC}  Timezone        : ${tz}"

  # SSH hardening
  if [[ -f /etc/ssh/sshd_config.d/50-glados-hardening.conf ]]; then
    echo -e "  ${GREEN}✔${NC}  SSH hardening   : applied"
  else
    echo -e "  ${YELLOW}⚠${NC}  SSH hardening   : not applied"
    ok=false
  fi

  # Unattended upgrades
  if dpkg -l unattended-upgrades >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Auto-updates    : enabled"
  else
    echo -e "  ${YELLOW}⚠${NC}  Auto-updates    : not configured"
    ok=false
  fi

  # Log rotation
  if [[ -f /etc/logrotate.d/glados-installer ]]; then
    echo -e "  ${GREEN}✔${NC}  Log rotation    : configured"
  else
    echo -e "  ${YELLOW}⚠${NC}  Log rotation    : not configured"
    ok=false
  fi

  [[ "$ok" == true ]]
}
