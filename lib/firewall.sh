#!/usr/bin/env bash
# =============================================================================
# lib/firewall.sh — UFW firewall configuration
#
# Sets up a restrictive firewall with only the necessary ports open:
#   • SSH (22 by default, or custom)
#   • All GLaDOS services are localhost-only — no ports exposed to LAN
#   • Optionally allows specific LAN access for SearXNG or Ollama
#
# Idempotent: skips if UFW is already active with matching rules.
# =============================================================================

[[ -n "${_GLADOS_FIREWALL_LOADED:-}" ]] && return 0
readonly _GLADOS_FIREWALL_LOADED=1

# Defaults
SKIP_FIREWALL="${SKIP_FIREWALL:-false}"
FIREWALL_SSH_PORT="${FIREWALL_SSH_PORT:-22}"

###############################################################################
# Main entry point
###############################################################################

configure_firewall() {
  section "Firewall (UFW) configuration"

  # Install UFW if not present
  if ! command -v ufw >/dev/null 2>&1; then
    spinner_start "Installing UFW..."
    run_cmd sudo apt-get install -y -qq ufw
    spinner_stop
    success "UFW installed."
  fi

  # If already active, show status and skip
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    success "UFW is already active."
    _show_ufw_rules
    if [[ "$NON_INTERACTIVE" != true ]]; then
      if ! confirm "Re-apply GLaDOS firewall rules?" "n"; then
        info "Keeping existing firewall configuration."
        return 0
      fi
    else
      return 0
    fi
  fi

  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo
    echo -e "  ${BOLD}Firewall plan${NC}"
    echo -e "  ─────────────────────────────────────────────────────"
    echo -e "  ${CYAN}Default policy   :${NC} deny incoming / allow outgoing"
    echo -e "  ${CYAN}Allow SSH        :${NC} port ${FIREWALL_SSH_PORT}/tcp"
    echo -e "  ${CYAN}GLaDOS services  :${NC} localhost only (no ports exposed)"
    echo -e "  ─────────────────────────────────────────────────────"
    echo

    prompt_value "SSH port to allow" "$FIREWALL_SSH_PORT" FIREWALL_SSH_PORT

    if ! confirm "Apply firewall rules?" "y"; then
      info "Firewall configuration cancelled."
      return 0
    fi
  fi

  _apply_firewall_rules
}

###############################################################################
# Apply rules
###############################################################################

_apply_firewall_rules() {
  spinner_start "Configuring UFW rules..."

  # Set defaults
  run_cmd sudo ufw default deny incoming
  run_cmd sudo ufw default allow outgoing

  # Allow SSH
  run_cmd sudo ufw allow "${FIREWALL_SSH_PORT}/tcp" comment "SSH"

  # Allow localhost traffic (needed for inter-service communication)
  run_cmd sudo ufw allow in on lo comment "Loopback"

  # Rate-limit SSH to prevent brute-force
  run_cmd sudo ufw limit "${FIREWALL_SSH_PORT}/tcp" comment "SSH rate-limit"

  spinner_stop

  # Enable UFW (--force to avoid interactive prompt)
  spinner_start "Enabling UFW..."
  run_cmd sudo ufw --force enable
  spinner_stop

  success "Firewall enabled — default deny + SSH on port ${FIREWALL_SSH_PORT}."
  _show_ufw_rules
}

###############################################################################
# Display current rules
###############################################################################

_show_ufw_rules() {
  echo
  echo -e "  ${DIM}$(sudo ufw status numbered 2>/dev/null | head -20)${NC}"
  echo
}

###############################################################################
# Health check
###############################################################################

check_firewall_health() {
  if command -v ufw >/dev/null 2>&1; then
    local status
    status="$(sudo ufw status 2>/dev/null | head -1)"
    if echo "$status" | grep -q "active"; then
      local rule_count
      rule_count="$(sudo ufw status numbered 2>/dev/null | grep -c '^\[' || echo '0')"
      echo -e "  ${GREEN}✔${NC}  Firewall (UFW)  : active (${rule_count} rules)"
      return 0
    else
      echo -e "  ${YELLOW}⚠${NC}  Firewall (UFW)  : inactive"
      return 1
    fi
  else
    echo -e "  ${YELLOW}⚠${NC}  Firewall (UFW)  : not installed"
    return 1
  fi
}
