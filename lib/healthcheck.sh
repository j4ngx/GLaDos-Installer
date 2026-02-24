#!/usr/bin/env bash
# =============================================================================
# lib/healthcheck.sh — Automated health monitoring via cron
#
# Installs a lightweight cron job that periodically checks the status of all
# GLaDOS services (Ollama, OpenClaw, SearXNG, Docker).  When a service is
# detected as down it:
#   1. Logs the event to ~/glados-installer/logs/healthcheck.log
#   2. Optionally sends a Telegram notification (if configured)
#
# The check runs every 5 minutes by default.
# =============================================================================

[[ -n "${_GLADOS_HEALTHCHECK_LOADED:-}" ]] && return 0
readonly _GLADOS_HEALTHCHECK_LOADED=1

SKIP_HEALTHCHECK="${SKIP_HEALTHCHECK:-false}"
readonly HEALTHCHECK_SCRIPT="$HOME/.local/bin/glados-healthcheck"
readonly HEALTHCHECK_LOG="${LOG_DIR}/healthcheck.log"
readonly HEALTHCHECK_CRON_INTERVAL="*/5"   # every 5 minutes

###############################################################################
# Main entry point
###############################################################################

configure_healthcheck() {
  section "Automated health monitoring (cron)"

  if [[ "$SKIP_HEALTHCHECK" == true ]]; then
    info "Health monitoring skipped (--skip-healthcheck)."
    return 0
  fi

  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo
    echo -e "  ${BOLD}Health monitoring${NC}"
    echo -e "  ─────────────────────────────────────────────────────"
    echo -e "  ${CYAN}Interval  :${NC} every 5 minutes"
    echo -e "  ${CYAN}Checks    :${NC} Ollama API, OpenClaw gateway, SearXNG, Docker"
    echo -e "  ${CYAN}Log       :${NC} ${HEALTHCHECK_LOG}"
    echo -e "  ${CYAN}Telegram  :${NC} notify on failure (if configured)"
    echo -e "  ─────────────────────────────────────────────────────"
    echo

    if ! confirm "Install automated health monitoring?" "y"; then
      info "Health monitoring skipped."
      return 0
    fi
  fi

  _write_healthcheck_script
  _install_healthcheck_cron

  success "Health monitoring installed (cron: ${HEALTHCHECK_CRON_INTERVAL} * * * *)."
}

###############################################################################
# Write the check script
###############################################################################

_write_healthcheck_script() {
  mkdir -p "$(dirname "$HEALTHCHECK_SCRIPT")"
  mkdir -p "$(dirname "$HEALTHCHECK_LOG")"

  cat >"$HEALTHCHECK_SCRIPT" <<HEALTHCHECK
#!/usr/bin/env bash
# ==========================================================================
# glados-healthcheck — Check all GLaDOS services and log/alert on failures
# Runs from cron every 5 minutes.
# ==========================================================================

set -euo pipefail

LOG_FILE="\${GLADOS_HEALTHCHECK_LOG:-\$HOME/glados-installer/logs/healthcheck.log}"
TIMESTAMP="\$(date '+%Y-%m-%d %H:%M:%S')"
SEARXNG_PORT="${SEARXNG_PORT}"

failures=()

# --- Ollama ---
if ! curl -sfm 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  failures+=("Ollama API unreachable on :11434")
fi

# --- OpenClaw gateway ---
if command -v openclaw >/dev/null 2>&1; then
  if ! openclaw gateway status >/dev/null 2>&1; then
    failures+=("OpenClaw gateway not running")
  fi
fi

# --- SearXNG ---
if curl -sfm 3 "http://127.0.0.1:\${SEARXNG_PORT}/healthz" >/dev/null 2>&1; then
  : # OK
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "glados-searxng"; then
  # Container exists but healthz fails
  failures+=("SearXNG container running but /healthz failing")
fi

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    failures+=("Docker daemon not responding")
  fi
fi

# --- Report ---
if [[ \${#failures[@]} -eq 0 ]]; then
  echo "[\${TIMESTAMP}] OK — all services healthy" >> "\$LOG_FILE"
  exit 0
fi

# Log failures
for f in "\${failures[@]}"; do
  echo "[\${TIMESTAMP}] FAIL — \${f}" >> "\$LOG_FILE"
done

# Send alert via direct notification (not through the LLM)
if command -v openclaw >/dev/null 2>&1; then
  msg="⚠️ GLaDOS Health Alert (\$(hostname)):\n"
  for f in "\${failures[@]}"; do
    msg+="  • \${f}\n"
  done
  msg+="Time: \${TIMESTAMP}"
  # Try openclaw notify first (direct Telegram), fall back to logger
  openclaw notify "\${msg}" 2>/dev/null \
    || logger -t glados-health -p user.warning "\${msg}" 2>/dev/null \
    || true
fi

exit 1
HEALTHCHECK

  chmod +x "$HEALTHCHECK_SCRIPT"
  debug "Healthcheck script written to ${HEALTHCHECK_SCRIPT}"
}

###############################################################################
# Install cron job
###############################################################################

_install_healthcheck_cron() {
  local cron_line="${HEALTHCHECK_CRON_INTERVAL} * * * * GLADOS_HEALTHCHECK_LOG=${HEALTHCHECK_LOG} ${HEALTHCHECK_SCRIPT} >/dev/null 2>&1"
  local cron_marker="# glados-healthcheck"

  # Check if already installed
  if crontab -l 2>/dev/null | grep -q "glados-healthcheck"; then
    success "Healthcheck cron job already installed."
    return 0
  fi

  # Append to existing crontab
  (crontab -l 2>/dev/null; echo "${cron_line}   ${cron_marker}") | crontab -
  success "Cron job installed: ${HEALTHCHECK_CRON_INTERVAL} * * * *"
}

###############################################################################
# Health check (meta — checks if the monitoring itself is set up)
###############################################################################

check_healthcheck_status() {
  if [[ -x "$HEALTHCHECK_SCRIPT" ]] && crontab -l 2>/dev/null | grep -q "glados-healthcheck"; then
    echo -e "  ${GREEN}✔${NC}  Health monitor  : active (cron ${HEALTHCHECK_CRON_INTERVAL}m)"
    return 0
  else
    echo -e "  ${YELLOW}⚠${NC}  Health monitor  : not configured"
    return 1
  fi
}
