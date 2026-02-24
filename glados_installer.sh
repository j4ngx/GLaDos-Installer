#!/usr/bin/env bash
# =============================================================================
# GLaDOS Installer — main entry point
# =============================================================================
# Orchestrates the installation of:
#   • Ollama + LLM model (local inference)
#   • OpenClaw personal AI assistant
#   • OpenClaw ↔ Ollama integration
#   • whisper.cpp — offline voice/speech-to-text
#   • Piper TTS  — offline text-to-speech (multi-voice)
#   • SearXNG    — self-hosted web-search (real-time internet)
#   • Swap file, UFW firewall, SSH/system hardening
#   • GPU acceleration (NVIDIA / AMD auto-detection)
#   • Cron-based health monitoring
#   • Backup/restore and uninstall utilities
#   • (OPTIONAL) Telegram channel (bot)
#
# Target: Debian 13  ·  Intel N4000 / 8 GB RAM  ·  English only
#
# shellcheck disable=SC2034   # colour vars not always referenced directly
# =============================================================================

set -Eeuo pipefail

###############################################################################
# Resolve script directory and source all library modules
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

_source_lib() {
  local lib="${LIB_DIR}/${1}"
  [[ -f "$lib" ]] || { echo "FATAL: missing library ${lib}"; exit 1; }
  # shellcheck source=/dev/null
  source "$lib"
}

_source_lib common.sh
_source_lib tui.sh
_source_lib preflight.sh
_source_lib network.sh
_source_lib swap.sh
_source_lib gpu.sh
_source_lib packages.sh
_source_lib docker.sh
_source_lib ollama.sh
_source_lib openclaw.sh
_source_lib audio.sh
_source_lib internet.sh
_source_lib telegram.sh
_source_lib firewall.sh
_source_lib hardening.sh
_source_lib healthcheck.sh
_source_lib backup.sh

# LOG_FILE timestamp is set in common.sh; export so all subshells share it
export LOG_FILE

###############################################################################
# ASCII-art banner (delegates to TUI library)
###############################################################################

print_banner() {
  tui_glados_banner
}

###############################################################################
# Help
###############################################################################

print_usage() {
  cat <<USAGE
${BOLD}${INSTALLER_NAME}${NC} v${INSTALLER_VERSION}

${BOLD}USAGE${NC}
  $(basename "$0") [OPTIONS]

${BOLD}CORE OPTIONS${NC}
  --model <tag>           Ollama model tag        (default: ${OLLAMA_META_MODEL_TAG})
  --agent-name <name>     OpenClaw agent label    (default: ${GLADOS_AGENT_NAME})
  --whisper-model <size>  Whisper STT model size  (default: ${WHISPER_MODEL})
                          Values: tiny · base · small · medium · large
  --piper-voice <name>    Piper TTS voice name    (default: ${PIPER_SELECTED_VOICE})
  --static-ip <ip>        Set a static IP         (e.g. 192.168.1.100)
  --static-gw <ip>        Static IP gateway       (e.g. 192.168.1.1)
  --static-dns <ip>       Static IP DNS server    (default: 1.1.1.1)
  --static-mask <cidr>    Static IP netmask CIDR  (default: 24)

${BOLD}SERVER TUNING${NC}
  --swap-size <MB>        Swap file size in MB    (default: auto — match RAM, cap 8 GB)
  --ssh-port <port>       SSH port for firewall   (default: ${FIREWALL_SSH_PORT})
  --hostname <name>       Set system hostname     (empty = prompt interactively)
  --timezone <tz>         Set timezone             (e.g. Europe/Madrid, default: auto-detect)
  --http-proxy <url>      HTTP proxy URL          (e.g. http://proxy:3128)
  --https-proxy <url>     HTTPS proxy URL

${BOLD}FEATURE FLAGS${NC}
  --skip-static-ip        Skip static IP configuration prompt
  --skip-swap             Skip swap file creation
  --skip-gpu              Skip GPU detection and acceleration setup
  --skip-firewall         Skip UFW firewall configuration
  --skip-hardening        Skip system hardening (hostname, SSH, upgrades)
  --skip-healthcheck      Skip cron health monitoring setup
  --skip-audio            Do not install voice input/output (Whisper + Piper)
  --skip-internet         Do not deploy SearXNG web-search
  --skip-telegram         Skip Telegram channel configuration

${BOLD}RUN-MODE FLAGS${NC}
  --non-interactive       Accept all defaults without prompting
  --dry-run               Show what would be done without making changes
  --verbose               Enable debug-level output
  --status                Show current installation status and exit
  --help, -h              Show this message and exit

${BOLD}MAINTENANCE${NC}
  --backup                Create a backup of GLaDOS configuration
  --restore [file]        Restore from a backup archive
  --uninstall             Remove all GLaDOS components

${BOLD}ENVIRONMENT VARIABLES${NC}
  TELEGRAM_BOT_TOKEN      Telegram bot token (export before running)
  GLADOS_VOICE_MODEL      Default LLM model tag for glados-voice wrapper
  HTTP_PROXY              HTTP proxy (alternative to --http-proxy)
  HTTPS_PROXY             HTTPS proxy (alternative to --https-proxy)

${BOLD}EXAMPLES${NC}
  # Full install with defaults (recommended)
  $(basename "$0")

  # Voice only, no internet search, no Telegram
  $(basename "$0") --skip-internet --skip-telegram

  # Custom model + all features
  export TELEGRAM_BOT_TOKEN="123456:ABCdef..."
  $(basename "$0") --model llama3.1:instruct --agent-name GLaDOS

  # Preview without changes
  $(basename "$0") --dry-run --verbose

  # Tiny Whisper model with custom TTS voice
  $(basename "$0") --whisper-model tiny --piper-voice en_US-lessac-high

  # Pre-set a static IP (non-interactive)
  $(basename "$0") --static-ip 192.168.1.100 --static-gw 192.168.1.1

  # Server hardening with custom hostname and timezone
  $(basename "$0") --hostname glados-server --timezone Europe/Madrid

  # Minimal install: skip heavy optional features
  $(basename "$0") --skip-audio --skip-internet --skip-telegram --skip-gpu

  # Behind a corporate proxy
  $(basename "$0") --http-proxy http://proxy:3128 --https-proxy http://proxy:3128

  # Backup current state
  $(basename "$0") --backup

  # Uninstall everything
  $(basename "$0") --uninstall

USAGE
}

###############################################################################
# CLI argument parsing
###############################################################################

parse_args() {
  # Maintenance modes (exit early)
  RUN_BACKUP=false
  RUN_RESTORE=false
  RUN_UNINSTALL=false
  RESTORE_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)
        shift; [[ $# -gt 0 ]] || fail "--model requires a value."
        OLLAMA_META_MODEL_TAG="$1"
        ;;
      --agent-name)
        shift; [[ $# -gt 0 ]] || fail "--agent-name requires a value."
        GLADOS_AGENT_NAME="$1"
        ;;
      --whisper-model)
        shift; [[ $# -gt 0 ]] || fail "--whisper-model requires a value."
        case "$1" in
          tiny|base|small|medium|large|large-v2|large-v3) WHISPER_MODEL="$1" ;;
          *) warn "Unknown Whisper model size '${1}' — falling back to '${WHISPER_DEFAULT_MODEL}'.";
             WHISPER_MODEL="$WHISPER_DEFAULT_MODEL" ;;
        esac
        ;;
      --piper-voice)
        shift; [[ $# -gt 0 ]] || fail "--piper-voice requires a value."
        PIPER_VOICE="$1"
        ;;
      --static-ip)
        shift; [[ $# -gt 0 ]] || fail "--static-ip requires a value."
        STATIC_IP="$1"
        ;;
      --static-gw)
        shift; [[ $# -gt 0 ]] || fail "--static-gw requires a value."
        STATIC_GATEWAY="$1"
        ;;
      --static-dns)
        shift; [[ $# -gt 0 ]] || fail "--static-dns requires a value."
        STATIC_DNS="$1"
        ;;
      --static-mask)
        shift; [[ $# -gt 0 ]] || fail "--static-mask requires a value."
        if ! [[ "$1" =~ ^[0-9]+$ ]] || (( $1 < 1 || $1 > 32 )); then
          fail "--static-mask must be 1-32 (CIDR prefix)."
        fi
        STATIC_NETMASK="$1"
        ;;
      --swap-size)
        shift; [[ $# -gt 0 ]] || fail "--swap-size requires a value."
        [[ "$1" =~ ^[0-9]+$ ]] || fail "--swap-size must be a positive integer (MB)."
        SWAP_SIZE_MB="$1"
        ;;
      --ssh-port)
        shift; [[ $# -gt 0 ]] || fail "--ssh-port requires a value."
        if ! [[ "$1" =~ ^[0-9]+$ ]] || (( $1 < 1 || $1 > 65535 )); then
          fail "--ssh-port must be 1-65535."
        fi
        FIREWALL_SSH_PORT="$1"
        ;;
      --hostname)
        shift; [[ $# -gt 0 ]] || fail "--hostname requires a value."
        GLADOS_HOSTNAME="$1"
        ;;
      --timezone)
        shift; [[ $# -gt 0 ]] || fail "--timezone requires a value."
        GLADOS_TIMEZONE="$1"
        ;;
      --http-proxy)
        shift; [[ $# -gt 0 ]] || fail "--http-proxy requires a value."
        HTTP_PROXY="$1"
        ;;
      --https-proxy)
        shift; [[ $# -gt 0 ]] || fail "--https-proxy requires a value."
        HTTPS_PROXY="$1"
        ;;
      --skip-static-ip)   SKIP_STATIC_IP=true ;;
      --skip-swap)        SKIP_SWAP=true ;;
      --skip-gpu)         SKIP_GPU=true ;;
      --skip-firewall)    SKIP_FIREWALL=true ;;
      --skip-hardening)   SKIP_HARDENING=true ;;
      --skip-healthcheck) SKIP_HEALTHCHECK=true ;;
      --non-interactive)  NON_INTERACTIVE=true ;;
      --skip-telegram)    SKIP_TELEGRAM=true ;;
      --skip-audio)       SKIP_AUDIO=true ;;
      --skip-internet)    SKIP_INTERNET=true ;;
      --dry-run)          DRY_RUN=true ;;
      --verbose)          VERBOSE=true ;;
      --status)           SHOW_STATUS=true ;;
      --backup)           RUN_BACKUP=true ;;
      --restore)
        RUN_RESTORE=true
        if [[ $# -gt 1 ]] && [[ "$2" != --* ]]; then
          shift; RESTORE_FILE="$1"
        fi
        ;;
      --uninstall)        RUN_UNINSTALL=true ;;
      --help|-h)          print_usage; exit 0 ;;
      *)                  fail "Unknown argument: $1  (use --help for usage)" ;;
    esac
    shift
  done

  # Export proxy vars if set
  [[ -n "$HTTP_PROXY" ]]  && { export HTTP_PROXY; export http_proxy="$HTTP_PROXY"; }
  [[ -n "$HTTPS_PROXY" ]] && { export HTTPS_PROXY; export https_proxy="$HTTPS_PROXY"; }
  [[ -n "$NO_PROXY" ]]    && { export NO_PROXY; export no_proxy="$NO_PROXY"; }

  # Calculate total step count dynamically from enabled pipeline stages.
  # Always-on: preflight, base_packages, docker, ollama, pull_model,
  #            openclaw, configure_openclaw_ollama  (7 steps)
  TOTAL_STEPS=7
  [[ "$SKIP_STATIC_IP"   != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_SWAP"        != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_GPU"         != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_AUDIO"       != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_INTERNET"    != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  TOTAL_STEPS=$((TOTAL_STEPS + 1))  # openclaw gateway & daemon setup (always runs)
  [[ "$SKIP_TELEGRAM"    != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_FIREWALL"    != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_HARDENING"   != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$SKIP_HEALTHCHECK" != true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
}

###############################################################################
# Cleanup / trap
###############################################################################

cleanup() {
  local exit_code=$?
  spinner_stop
  release_lock
  if [[ $exit_code -ne 0 ]]; then
    tui_failure_screen "$exit_code"
  fi
}

trap cleanup EXIT
trap 'fail "Interrupted by user (SIGINT)."'  INT
trap 'fail "Terminated (SIGTERM)."'          TERM

###############################################################################
# Interactive installation plan review
###############################################################################

###############################################################################
# Interactive installation plan review
###############################################################################

interactive_review() {
  [[ "$NON_INTERACTIVE" == true ]] && return

  tui_plan_card

  echo
  if confirm "Change the Ollama model? (current: ${OLLAMA_META_MODEL_TAG})" "n"; then
    prompt_value "Enter Ollama model tag" "$OLLAMA_META_MODEL_TAG" OLLAMA_META_MODEL_TAG
  fi

  echo
  confirm "Proceed with installation?" "y" || { info "Installation cancelled."; exit 0; }
  echo
}

###############################################################################
# Post-install health check + summary
###############################################################################

run_health_check() {
  echo
  TUI_BOX_COLOR="$TUI_ACCENT" tui_box "${ICON_CHART}  Post-install Health Check"

  local all_ok=true

  check_ollama_health   || all_ok=false
  check_openclaw_health || all_ok=false

  [[ "$SKIP_AUDIO"       != true ]] && { check_audio_health       || all_ok=false; }
  [[ "$SKIP_INTERNET"    != true ]] && { check_internet_health    || all_ok=false; }
  [[ "$SKIP_SWAP"        != true ]] && { check_swap_health        || all_ok=false; }
  [[ "$SKIP_GPU"         != true ]] && { check_gpu_health         || all_ok=false; }
  [[ "$SKIP_FIREWALL"    != true ]] && { check_firewall_health    || all_ok=false; }
  [[ "$SKIP_HARDENING"   != true ]] && { check_hardening_health   || all_ok=false; }
  [[ "$SKIP_HEALTHCHECK" != true ]] && { check_healthcheck_status || all_ok=false; }

  if command -v docker >/dev/null 2>&1; then
    tui_health_row "Docker" "$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" true
  fi

  tui_divider "single" "$TUI_MUTED"
  if [[ "$all_ok" == true ]]; then
    tui_notify "All health checks passed" "success"
  else
    tui_notify "Some checks failed — see output above" "warn"
  fi
}

print_summary() {
  local elapsed
  elapsed="$(elapsed_time "$INSTALL_START_EPOCH")"

  tui_completion_screen "$elapsed"

  echo
  TUI_BOX_COLOR="$TUI_SUCCESS" tui_box "${ICON_PACKAGE}  Installed Components" \
    "" \
    "$(printf '%b%-20s%b  %b%s%b' "$TUI_MUTED" 'Ollama + model' "$TUI_RESET" "$TUI_ACCENT2" "${OLLAMA_META_MODEL_TAG}" "$TUI_RESET")" \
    "$(printf '%b%-20s%b  %b%s%b' "$TUI_MUTED" 'OpenClaw agent' "$TUI_RESET" "$TUI_ACCENT2" "${GLADOS_AGENT_NAME}" "$TUI_RESET")" \
    "$([[ "$SKIP_SWAP"     != true ]] && printf '%b%-20s%b  %b%s MB%b' "$TUI_MUTED" 'Swap file' "$TUI_RESET" "$TUI_WHITE" "${SWAP_SIZE_MB}" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_GPU"      != true ]] && printf '%b%-20s%b  %bauto-detected%b' "$TUI_MUTED" 'GPU acceleration' "$TUI_RESET" "$TUI_WHITE" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_AUDIO"    != true ]] && printf '%b%-20s%b  %bWhisper %s + Piper %s%b' "$TUI_MUTED" 'Voice I/O' "$TUI_RESET" "$TUI_WHITE" "${WHISPER_MODEL}" "${PIPER_VOICE:-${PIPER_SELECTED_VOICE}}" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_INTERNET" != true ]] && printf '%b%-20s%b  %bhttp://127.0.0.1:%s%b' "$TUI_MUTED" 'SearXNG search' "$TUI_RESET" "$TUI_ACCENT2" "${SEARXNG_PORT}" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_TELEGRAM" != true ]] && printf '%b%-20s%b  %spending pairing%b' "$TUI_MUTED" 'Telegram' "$TUI_RESET" "$TUI_WARNING" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_FIREWALL" != true ]] && printf '%b%-20s%b  %bSSH port %s%b' "$TUI_MUTED" 'UFW firewall' "$TUI_RESET" "$TUI_WHITE" "${FIREWALL_SSH_PORT}" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_HARDENING" != true ]] && printf '%b%-20s%b  %bSSH + upgrades%b' "$TUI_MUTED" 'Hardening' "$TUI_RESET" "$TUI_WHITE" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_HEALTHCHECK" != true ]] && printf '%b%-20s%b  %bcron 5min%b' "$TUI_MUTED" 'Health monitor' "$TUI_RESET" "$TUI_WHITE" "$TUI_RESET" || echo '')"

  echo
  TUI_BOX_COLOR="$TUI_ACCENT2" tui_box "${ICON_BOLT}  Quick Reference" \
    "" \
    "$(printf '%b# Text chat%b'                    "$TUI_MUTED" "$TUI_RESET")" \
    "$(printf '%bopenclaw ask "Tell me something"%b' "$TUI_ACCENT2" "$TUI_RESET")" \
    "" \
    "$([[ "$SKIP_AUDIO" != true ]] && printf '%b# Voice chat%b' "$TUI_MUTED" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_AUDIO" != true ]] && printf '%bglados-voice%b'  "$TUI_ACCENT2" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_AUDIO" != true ]] && echo '' || echo '')" \
    "$([[ "$SKIP_INTERNET" != true ]] && printf '%b# Web search (auto by LLM)%b' "$TUI_MUTED" "$TUI_RESET" || echo '')" \
    "$([[ "$SKIP_INTERNET" != true ]] && printf '%bcurl -s http://127.0.0.1:%s/search?q=news\&format=json%b' "$TUI_ACCENT2" "${SEARXNG_PORT}" "$TUI_RESET" || echo '')" \
    "" \
    "$(printf '%b# Maintenance%b'                    "$TUI_MUTED" "$TUI_RESET")" \
    "$(printf '%b%s --backup   %b%b# backup config%b'  "$TUI_ACCENT2" "$(basename "$0")" "$TUI_RESET" "$TUI_MUTED" "$TUI_RESET")" \
    "$(printf '%b%s --restore  %b%b# restore%b'        "$TUI_ACCENT2" "$(basename "$0")" "$TUI_RESET" "$TUI_MUTED" "$TUI_RESET")" \
    "$(printf '%b%s --status   %b%b# health overview%b' "$TUI_ACCENT2" "$(basename "$0")" "$TUI_RESET" "$TUI_MUTED" "$TUI_RESET")" \
    "$(printf '%b%s --uninstall%b%b# remove all%b'     "$TUI_ACCENT2" "$(basename "$0")" "$TUI_RESET" "$TUI_MUTED" "$TUI_RESET")"

  echo
  tui_kv "Log" "$LOG_FILE" "${ICON_INFO}"
  echo

  run_health_check
  echo
  tui_notify "All ${TOTAL_STEPS} steps completed in ${elapsed}" "success"
}

###############################################################################
# --status: lightweight overview without installing
###############################################################################

show_status() {
  print_banner

  TUI_BOX_COLOR="$TUI_ACCENT" tui_box "${ICON_CHART}  GLaDOS Environment Status"
  echo

  check_ollama_health   || true
  check_openclaw_health || true

  check_network_static || true
  check_swap_health    || true
  check_gpu_health     || true

  # Only show audio/internet health if their components exist on disk
  if [[ -x "$(_whisper_binary)" ]] || [[ -x "${PIPER_BIN_DIR}/piper" ]]; then
    check_audio_health || true
  fi
  if [[ -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" ]]; then
    check_internet_health || true
  fi

  check_firewall_health    || true
  check_hardening_health   || true
  check_healthcheck_status || true

  if command -v docker >/dev/null 2>&1; then
    tui_health_row "Docker" "$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" true
  else
    tui_health_row "Docker" "not installed" false
  fi

  echo
  tui_kv "Log directory" "$LOG_DIR" "${ICON_INFO}"
  tui_kv "Backups"       "$BACKUP_DIR" "${ICON_PACKAGE}"
  echo
}

###############################################################################
# Main
###############################################################################

main() {
  INSTALL_START_EPOCH="$(date +%s)"

  print_banner
  parse_args "$@"

  # Maintenance modes — run and exit
  if [[ "$SHOW_STATUS" == true ]]; then
    show_status
    exit 0
  fi
  if [[ "$RUN_BACKUP" == true ]]; then
    run_backup
    exit 0
  fi
  if [[ "$RUN_RESTORE" == true ]]; then
    run_restore "${RESTORE_FILE:-}"
    exit 0
  fi
  if [[ "$RUN_UNINSTALL" == true ]]; then
    run_uninstall
    exit 0
  fi

  acquire_lock

  log "Starting ${INSTALLER_NAME} v${INSTALLER_VERSION}"
  log "Command: $0 $*"
  log "User: $(whoami)  Host: $(hostname)  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  [[ -n "$HTTP_PROXY" ]]  && log "HTTP proxy: ${HTTP_PROXY}"
  [[ -n "$HTTPS_PROXY" ]] && log "HTTPS proxy: ${HTTPS_PROXY}"

  preflight_checks
  interactive_review

  # Phase 1: System foundations
  [[ "$SKIP_STATIC_IP" != true ]] && configure_static_ip
  [[ "$SKIP_SWAP"      != true ]] && configure_swap
  [[ "$SKIP_GPU"       != true ]] && configure_gpu

  # Phase 2: Core packages and services
  install_base_packages
  install_docker_if_missing
  install_ollama
  pull_ollama_model
  install_openclaw

  run_openclaw_onboard

  configure_openclaw_ollama

  # Phase 3: Optional features
  if [[ "$SKIP_AUDIO" != true ]]; then
    install_audio            # whisper.cpp + piper + wrappers + openclaw voice config
  fi

  if [[ "$SKIP_INTERNET" != true ]]; then
    install_internet_search  # SearXNG via Docker + openclaw web-search config
  fi

  [[ "$SKIP_TELEGRAM" != true ]] && configure_openclaw_telegram

  # Phase 4: Server hardening and monitoring
  [[ "$SKIP_FIREWALL"    != true ]] && configure_firewall
  [[ "$SKIP_HARDENING"   != true ]] && configure_hardening
  [[ "$SKIP_HEALTHCHECK" != true ]] && configure_healthcheck

  print_summary
}

main "$@"
