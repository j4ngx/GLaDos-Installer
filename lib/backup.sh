#!/usr/bin/env bash
# =============================================================================
# lib/backup.sh — Backup, restore, and uninstall utilities
#
# Provides:
#   • Backup:    export GLaDOS configs, models list, and service state
#   • Restore:   import a previous backup archive
#   • Uninstall: cleanly remove all GLaDOS components
#
# Backup archive: ~/glados-installer/backups/glados_backup_<timestamp>.tar.gz
# =============================================================================

[[ -n "${_GLADOS_BACKUP_LOADED:-}" ]] && return 0
readonly _GLADOS_BACKUP_LOADED=1

readonly BACKUP_DIR="$HOME/glados-installer/backups"

###############################################################################
# Backup — export configuration and state
###############################################################################

run_backup() {
  section "Backup GLaDOS configuration"

  mkdir -p "$BACKUP_DIR"
  local timestamp
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  local backup_staging="/tmp/glados_backup_${timestamp}"
  local backup_file="${BACKUP_DIR}/glados_backup_${timestamp}.tar.gz"

  mkdir -p "$backup_staging"

  spinner_start "Collecting GLaDOS configuration..."

  # OpenClaw config
  if command -v openclaw >/dev/null 2>&1; then
    openclaw config export >"${backup_staging}/openclaw_config.json" 2>/dev/null || true
    debug "OpenClaw config exported."
  fi

  # Ollama model list
  if command -v ollama >/dev/null 2>&1; then
    ollama list >"${backup_staging}/ollama_models.txt" 2>/dev/null || true
    debug "Ollama model list saved."
  fi

  # SearXNG config
  if [[ -f "${SEARXNG_COMPOSE_DIR}/searxng/settings.yml" ]]; then
    cp "${SEARXNG_COMPOSE_DIR}/searxng/settings.yml" "${backup_staging}/searxng_settings.yml" 2>/dev/null || true
    debug "SearXNG settings saved."
  fi
  if [[ -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" ]]; then
    cp "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" "${backup_staging}/searxng_docker-compose.yml" 2>/dev/null || true
  fi

  # Network config
  if [[ -f /etc/network/interfaces ]]; then
    cp /etc/network/interfaces "${backup_staging}/network_interfaces" 2>/dev/null || true
  fi
  if [[ -f /etc/netplan/99-glados-static.yaml ]]; then
    cp /etc/netplan/99-glados-static.yaml "${backup_staging}/netplan_static.yaml" 2>/dev/null || true
  fi

  # SSH hardening
  if [[ -f /etc/ssh/sshd_config.d/50-glados-hardening.conf ]]; then
    cp /etc/ssh/sshd_config.d/50-glados-hardening.conf "${backup_staging}/ssh_hardening.conf" 2>/dev/null || true
  fi

  # UFW rules
  if command -v ufw >/dev/null 2>&1; then
    sudo ufw status numbered 2>/dev/null | tee "${backup_staging}/ufw_rules.txt" >/dev/null || true
  fi

  # Piper voice config
  if [[ -d "${PIPER_INSTALL_DIR}/voices" ]]; then
    ls -la "${PIPER_INSTALL_DIR}/voices/" >"${backup_staging}/piper_voices.txt" 2>/dev/null || true
  fi

  # Crontab
  crontab -l >"${backup_staging}/crontab.txt" 2>/dev/null || true

  # System info snapshot
  cat >"${backup_staging}/system_info.txt" <<EOF
Backup created: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
User: $(whoami)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')
Kernel: $(uname -r)
Installer version: ${INSTALLER_VERSION:-unknown}
EOF

  spinner_stop

  # Create archive
  spinner_start "Creating backup archive..."
  tar -czf "$backup_file" -C "/tmp" "glados_backup_${timestamp}"
  rm -rf "$backup_staging"
  spinner_stop

  local size
  size="$(du -h "$backup_file" | cut -f1)"
  success "Backup saved: ${backup_file} (${size})"
}

###############################################################################
# Restore — import from a backup archive
###############################################################################

run_restore() {
  section "Restore GLaDOS configuration"

  local backup_file="$1"

  if [[ -z "$backup_file" ]]; then
    # List available backups
    echo
    echo -e "  ${BOLD}Available backups:${NC}"
    local count=0
    for f in "${BACKUP_DIR}"/glados_backup_*.tar.gz; do
      [[ -f "$f" ]] || continue
      count=$((count + 1))
      local size
      size="$(du -h "$f" | cut -f1)"
      local ts
      ts="$(basename "$f" | grep -oP '\d{8}_\d{6}')"
      echo -e "    ${count}. ${DIM}${ts}${NC}  (${size})  ${DIM}${f}${NC}"
    done

    if [[ $count -eq 0 ]]; then
      warn "No backups found in ${BACKUP_DIR}."
      return 1
    fi

    echo
    local _restore_choice=""
    prompt_value "Enter backup number to restore (or path)" "1" _restore_choice

    if [[ "$_restore_choice" =~ ^[0-9]+$ ]]; then
      local i=0
      for f in "${BACKUP_DIR}"/glados_backup_*.tar.gz; do
        [[ -f "$f" ]] || continue
        i=$((i + 1))
        if [[ $i -eq $_restore_choice ]]; then
          backup_file="$f"
          break
        fi
      done
    else
      backup_file="$_restore_choice"
    fi
  fi

  [[ -f "$backup_file" ]] || fail "Backup file not found: ${backup_file}"

  echo
  info "Restoring from: ${backup_file}"

  if ! confirm "This will overwrite current configuration. Continue?" "n"; then
    info "Restore cancelled."
    return 0
  fi

  local restore_dir="/tmp/glados_restore_$$"
  mkdir -p "$restore_dir"

  spinner_start "Extracting backup..."
  tar -xzf "$backup_file" -C "$restore_dir" --strip-components=1
  spinner_stop

  # Restore OpenClaw config
  if [[ -f "${restore_dir}/openclaw_config.json" ]] && command -v openclaw >/dev/null 2>&1; then
    openclaw config import "${restore_dir}/openclaw_config.json" 2>/dev/null || true
    success "OpenClaw configuration restored."
  fi

  # Restore SearXNG settings
  if [[ -f "${restore_dir}/searxng_settings.yml" ]]; then
    mkdir -p "${SEARXNG_COMPOSE_DIR}/searxng"
    cp "${restore_dir}/searxng_settings.yml" "${SEARXNG_COMPOSE_DIR}/searxng/settings.yml"
    chmod 600 "${SEARXNG_COMPOSE_DIR}/searxng/settings.yml"
    success "SearXNG settings restored."
  fi

  rm -rf "$restore_dir"
  success "Restore complete. Restart services to apply changes."
}

###############################################################################
# Uninstall — remove all GLaDOS components
###############################################################################

run_uninstall() {
  section "Uninstall GLaDOS"

  echo
  echo -e "  ${RED}${BOLD}WARNING:${NC} This will remove ALL GLaDOS components:${NC}"
  echo -e "    • OpenClaw CLI + gateway + config"
  echo -e "    • whisper.cpp + models"
  echo -e "    • Piper TTS + voices"
  echo -e "    • SearXNG Docker containers + data"
  echo -e "    • GLaDOS wrapper scripts"
  echo -e "    • Health monitoring cron"
  echo -e "    • Firewall rules (GLaDOS-specific)"
  echo
  echo -e "  ${YELLOW}Will NOT remove:${NC}"
  echo -e "    • Ollama (manage separately: sudo rm -rf /usr/local/bin/ollama)"
  echo -e "    • Docker engine"
  echo -e "    • System packages installed via APT"
  echo -e "    • SSH hardening (manage: /etc/ssh/sshd_config.d/50-glados-hardening.conf)"
  echo

  if ! confirm "Are you sure you want to uninstall GLaDOS?" "n"; then
    info "Uninstall cancelled."
    return 0
  fi

  if ! confirm "Create a backup before uninstalling?" "y"; then
    : # skip backup
  else
    run_backup
  fi

  # Stop and remove OpenClaw
  if command -v openclaw >/dev/null 2>&1; then
    info "Removing OpenClaw..."
    openclaw gateway stop 2>/dev/null || true
    openclaw uninstall 2>/dev/null || true
    success "OpenClaw removed."
  fi

  # Stop SearXNG
  if [[ -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    info "Stopping SearXNG containers..."
    local -a _compose
    read -ra _compose <<< "$(compose_cmd)"
    "${_compose[@]}" -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" --project-name glados-searxng down -v 2>/dev/null || true
    rm -rf "$SEARXNG_COMPOSE_DIR"
    success "SearXNG removed."
  fi

  # Remove whisper.cpp
  if [[ -d "$WHISPER_INSTALL_DIR" ]]; then
    rm -rf "$WHISPER_INSTALL_DIR"
    success "whisper.cpp removed."
  fi

  # Remove Piper
  if [[ -d "$PIPER_INSTALL_DIR" ]]; then
    rm -rf "$PIPER_INSTALL_DIR"
    rm -f "${PIPER_BIN_DIR}/piper"
    success "Piper TTS removed."
  fi

  # Remove wrapper scripts
  for script in glados-stt glados-tts glados-voice glados-healthcheck; do
    rm -f "${PIPER_BIN_DIR}/${script}"
  done
  success "GLaDOS scripts removed."

  # Remove healthcheck cron
  if crontab -l 2>/dev/null | grep -q "glados-healthcheck"; then
    crontab -l 2>/dev/null | grep -v "glados-healthcheck" | crontab -
    success "Healthcheck cron removed."
  fi

  # Remove swap file (optional)
  if [[ -f /swapfile ]] && grep -q "/swapfile" /etc/fstab 2>/dev/null; then
    if confirm "Remove GLaDOS swap file (/swapfile)?" "n"; then
      sudo swapoff /swapfile 2>/dev/null || true
      sudo rm -f /swapfile
      sudo sed -i '\|/swapfile|d' /etc/fstab
      success "Swap file removed."
    fi
  fi

  # Remove logrotate config
  sudo rm -f /etc/logrotate.d/glados-installer 2>/dev/null || true

  # Remove sysctl tweaks
  sudo rm -f /etc/sysctl.d/99-glados.conf 2>/dev/null || true

  echo
  success "GLaDOS uninstalled. Backup available in: ${BACKUP_DIR}"
  echo
  echo -e "  ${DIM}To also remove Ollama: curl -fsSL https://ollama.com/install.sh | OLLAMA_UNINSTALL=1 sh${NC}"
  echo -e "  ${DIM}To remove logs:        rm -rf ~/glados-installer${NC}"
  echo
}
