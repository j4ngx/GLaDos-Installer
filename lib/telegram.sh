#!/usr/bin/env bash
# =============================================================================
# lib/telegram.sh — Telegram bot channel configuration
# =============================================================================

[[ -n "${_GLADOS_TELEGRAM_LOADED:-}" ]] && return 0
readonly _GLADOS_TELEGRAM_LOADED=1

configure_openclaw_telegram() {
  section "Telegram channel configuration"
  require_command openclaw "OpenClaw CLI"

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo
    info "TELEGRAM_BOT_TOKEN is not set. You need a token from @BotFather on Telegram."

    if [[ "$NON_INTERACTIVE" == true ]]; then
      warn "Non-interactive mode — cannot prompt for token. Skipping Telegram setup."
      return
    fi

    echo
    read -r -s -p "$(echo -e "${CYAN}? ${NC}Paste your Telegram bot token (hidden): ")" TELEGRAM_BOT_TOKEN
    echo
  fi

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    warn "No Telegram token provided — skipping."
    return
  fi

  # Basic format validation
  if ! [[ "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    warn "Token format looks invalid (expected '<id>:<hash>')."
    confirm "Continue anyway?" "n" || { warn "Telegram setup cancelled."; return; }
  fi

  log "Configuring Telegram channel (token not logged for security)."
  oc_config_set channels.telegram.enabled true

  # Pass token via environment to avoid exposing it in `ps` process listing.
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}" \
    oc_config_set channels.telegram.botToken --from-env TELEGRAM_BOT_TOKEN
  oc_config_set channels.telegram.dmPolicy "pairing"

  success "Telegram channel configured."

  # Security: clear token from process environment immediately
  unset TELEGRAM_BOT_TOKEN
  debug "TELEGRAM_BOT_TOKEN cleared from environment."

  echo
  echo -e "  ${BOLD}Telegram next steps:${NC}"
  echo -e "    1. Open a chat with your bot → send \"hi\""
  echo -e "    2. List pending requests:  ${DIM}openclaw pairing list telegram${NC}"
  echo -e "    3. Approve pairing:        ${DIM}openclaw pairing approve telegram <CODE>${NC}"
  echo
}
