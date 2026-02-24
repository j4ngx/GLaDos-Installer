#!/usr/bin/env bash
# =============================================================================
# GLaDOS Installer — main entry point
# =============================================================================
# Orchestrates the installation of:
#   • Ollama + LLM model (local inference)
#   • OpenClaw personal AI assistant
#   • OpenClaw ↔ Ollama integration
#   • (NEW) whisper.cpp — offline voice/speech-to-text
#   • (NEW) Piper TTS  — offline text-to-speech
#   • (NEW) SearXNG    — self-hosted web-search (real-time internet)
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
_source_lib preflight.sh
_source_lib packages.sh
_source_lib docker.sh
_source_lib ollama.sh
_source_lib openclaw.sh
_source_lib audio.sh
_source_lib internet.sh
_source_lib telegram.sh

# LOG_FILE timestamp is set in common.sh; export so all subshells share it
export LOG_FILE

###############################################################################
# ASCII-art banner
###############################################################################

print_banner() {
  clear 2>/dev/null || true
  echo -e "${MAGENTA}"
  cat <<'BANNER'

    ██████╗ ██╗      █████╗ ██████╗  ██████╗ ███████╗
   ██╔════╝ ██║     ██╔══██╗██╔══██╗██╔═══██╗██╔════╝
   ██║  ███╗██║     ███████║██║  ██║██║   ██║███████╗
   ██║   ██║██║     ██╔══██║██║  ██║██║   ██║╚════██║
   ╚██████╔╝███████╗██║  ██║██████╔╝╚██████╔╝███████║
    ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚══════╝

       Local LLM · Voice I/O · Web Search · Telegram

BANNER
  echo -e "${NC}"
  echo -e "  ${CYAN}${BOLD}${INSTALLER_NAME}${NC}  ${DIM}v${INSTALLER_VERSION}${NC}"
  echo
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

${BOLD}FEATURE FLAGS${NC}
  --skip-audio            Do not install voice input/output (Whisper + Piper)
  --skip-internet         Do not deploy SearXNG web-search
  --skip-telegram         Skip Telegram channel configuration
  --skip-onboard          Skip 'openclaw onboard' wizard (run manually later)

${BOLD}RUN-MODE FLAGS${NC}
  --non-interactive       Accept all defaults without prompting
  --dry-run               Show what would be done without making changes
  --verbose               Enable debug-level output
  --status                Show current installation status and exit
  --help, -h              Show this message and exit

${BOLD}ENVIRONMENT VARIABLES${NC}
  TELEGRAM_BOT_TOKEN      Telegram bot token (export before running)

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

  # Tiny Whisper model (fastest on weak hardware)
  $(basename "$0") --whisper-model tiny

USAGE
}

###############################################################################
# CLI argument parsing
###############################################################################

parse_args() {
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
      --non-interactive)  NON_INTERACTIVE=true ;;
      --skip-telegram)    SKIP_TELEGRAM=true ;;
      --skip-onboard)     SKIP_ONBOARD=true ;;
      --skip-audio)       SKIP_AUDIO=true ;;
      --skip-internet)    SKIP_INTERNET=true ;;
      --dry-run)          DRY_RUN=true ;;
      --verbose)          VERBOSE=true ;;
      --status)           SHOW_STATUS=true ;;
      --help|-h)          print_usage; exit 0 ;;
      *)                  fail "Unknown argument: $1  (use --help for usage)" ;;
    esac
    shift
  done

  # Recalculate total step count after all flags are parsed
  TOTAL_STEPS=10
  [[ "$SKIP_AUDIO"    == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
  [[ "$SKIP_INTERNET" == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
  [[ "$SKIP_ONBOARD"  == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
  [[ "$SKIP_TELEGRAM" == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
}

###############################################################################
# Cleanup / trap
###############################################################################

cleanup() {
  local exit_code=$?
  spinner_stop
  release_lock
  if [[ $exit_code -ne 0 ]]; then
    echo
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  Installation failed (exit code ${exit_code}).${NC}"
    echo -e "${RED}  Log: ${LOG_FILE}${NC}"
    echo -e "${RED}  Re-run this script to resume — completed steps are skipped.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi
}

trap cleanup EXIT
trap 'fail "Interrupted by user (SIGINT)."'  INT
trap 'fail "Terminated (SIGTERM)."'          TERM

###############################################################################
# Interactive installation plan review
###############################################################################

interactive_review() {
  [[ "$NON_INTERACTIVE" == true ]] && return

  echo
  echo -e "  ${BOLD}Installation Plan${NC}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo -e "  ${CYAN}LLM model        :${NC} ${OLLAMA_META_MODEL_TAG}"
  echo -e "  ${CYAN}Agent name       :${NC} ${GLADOS_AGENT_NAME}"
  echo -e "  ${CYAN}Voice (Whisper)  :${NC} $( [[ "$SKIP_AUDIO"    == true ]] && echo 'skip' || echo "model: ${WHISPER_MODEL}" )"
  echo -e "  ${CYAN}Web search       :${NC} $( [[ "$SKIP_INTERNET"  == true ]] && echo 'skip' || echo "SearXNG on :${SEARXNG_PORT}" )"
  echo -e "  ${CYAN}Telegram         :${NC} $( [[ "$SKIP_TELEGRAM"  == true ]] && echo 'skip' || echo 'configure' )"
  echo -e "  ${CYAN}Onboard wizard   :${NC} $( [[ "$SKIP_ONBOARD"   == true ]] && echo 'skip' || echo 'run' )"
  echo -e "  ${CYAN}Dry run          :${NC} ${DRY_RUN}"
  echo -e "  ${CYAN}Log file         :${NC} ${LOG_FILE}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo

  if confirm "Change the Ollama model? (current: ${OLLAMA_META_MODEL_TAG})" "n"; then
    prompt_value "Enter Ollama model tag" "$OLLAMA_META_MODEL_TAG" OLLAMA_META_MODEL_TAG
  fi

  confirm "Proceed with installation?" "y" || { info "Installation cancelled."; exit 0; }
}

###############################################################################
# Post-install health check + summary
###############################################################################

run_health_check() {
  echo
  echo -e "  ${BOLD}Post-install health check${NC}"
  echo -e "  ─────────────────────────────────────────────────────"

  local all_ok=true

  check_ollama_health   || all_ok=false
  check_openclaw_health || all_ok=false

  [[ "$SKIP_AUDIO"    != true ]] && { check_audio_health   || all_ok=false; }
  [[ "$SKIP_INTERNET" != true ]] && { check_internet_health || all_ok=false; }

  if command -v docker >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Docker          : $(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  fi

  echo -e "  ─────────────────────────────────────────────────────"
  if [[ "$all_ok" == true ]]; then
    success "All health checks passed."
  else
    warn "Some checks failed — see output above."
  fi
}

print_summary() {
  local elapsed
  elapsed="$(elapsed_time "$INSTALL_START_EPOCH")"

  echo
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ${BOLD}GLaDOS environment is ready!${NC}  ${DIM}(${elapsed})${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${BOLD}Installed components:${NC}"
  echo -e "    • Ollama + model: ${CYAN}${OLLAMA_META_MODEL_TAG}${NC}"
  echo -e "    • OpenClaw CLI + gateway  (agent: ${CYAN}${GLADOS_AGENT_NAME}${NC})"
  [[ "$SKIP_AUDIO"    != true ]] && echo -e "    • whisper.cpp (${CYAN}${WHISPER_MODEL}${NC}) + Piper TTS"
  [[ "$SKIP_INTERNET" != true ]] && echo -e "    • SearXNG → http://127.0.0.1:${SEARXNG_PORT}"
  [[ "$SKIP_TELEGRAM" != true ]] && echo -e "    • Telegram channel (pending pairing)"
  echo
  echo -e "  ${BOLD}Quick reference:${NC}"
  echo
  echo -e "    ${DIM}# Text chat${NC}"
  echo -e "    openclaw ask \"Tell me something interesting\""
  echo
  if [[ "$SKIP_AUDIO" != true ]]; then
    echo -e "    ${DIM}# Voice chat (speak → model → speech reply)${NC}"
    echo -e "    glados-voice"
    echo -e "    glados-voice --record-secs 10 --no-tts"
    echo -e "    echo 'Hello' | glados-tts"
    echo -e "    glados-stt 5"
    echo
  fi
  if [[ "$SKIP_INTERNET" != true ]]; then
    echo -e "    ${DIM}# Search the web (used automatically by the LLM)${NC}"
    echo -e "    curl -s 'http://127.0.0.1:${SEARXNG_PORT}/search?q=latest+news&format=json' | jq '.results[0].title'"
    echo
  fi
  if [[ "$SKIP_TELEGRAM" != true ]]; then
    echo -e "    ${DIM}# Telegram pairing${NC}"
    echo -e "    openclaw pairing list telegram"
    echo -e "    openclaw pairing approve telegram <CODE>"
    echo
  fi
  echo -e "    openclaw status  ·  openclaw gateway status  ·  openclaw dashboard"
  echo -e "    ollama list"
  echo
  echo -e "  ${BOLD}Log:${NC} ${DIM}${LOG_FILE}${NC}"
  echo

  run_health_check
  echo
  success "All ${TOTAL_STEPS} steps completed in ${elapsed}."
}

###############################################################################
# --status: lightweight overview without installing
###############################################################################

show_status() {
  print_banner
  echo -e "  ${BOLD}GLaDOS Environment Status${NC}"
  echo -e "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  check_ollama_health   || true
  check_openclaw_health || true

  # Only show audio/internet health if their components exist on disk
  if [[ -x "$(_whisper_binary)" ]] || [[ -x "${PIPER_BIN_DIR}/piper" ]]; then
    check_audio_health || true
  fi
  if [[ -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" ]]; then
    check_internet_health || true
  fi

  if command -v docker >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Docker          : $(docker --version 2>/dev/null)"
  else
    echo -e "  ${YELLOW}⚠${NC}  Docker          : not installed"
  fi
  echo
  echo -e "  ${BOLD}Log directory:${NC} ${DIM}${LOG_DIR}${NC}"
  echo
}

###############################################################################
# Main
###############################################################################

main() {
  INSTALL_START_EPOCH="$(date +%s)"

  print_banner
  parse_args "$@"

  if [[ "$SHOW_STATUS" == true ]]; then
    show_status
    exit 0
  fi

  acquire_lock

  log "Starting ${INSTALLER_NAME} v${INSTALLER_VERSION}"
  log "Command: $0 $*"
  log "User: $(whoami)  Host: $(hostname)  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"

  preflight_checks
  interactive_review

  install_base_packages
  install_docker_if_missing
  install_ollama
  pull_ollama_model
  install_openclaw

  [[ "$SKIP_ONBOARD" != true ]] && run_openclaw_onboard

  configure_openclaw_ollama

  if [[ "$SKIP_AUDIO" != true ]]; then
    install_audio            # whisper.cpp + piper + wrappers + openclaw voice config
  fi

  if [[ "$SKIP_INTERNET" != true ]]; then
    install_internet_search  # SearXNG via Docker + openclaw web-search config
  fi

  [[ "$SKIP_TELEGRAM" != true ]] && configure_openclaw_telegram

  print_summary
}

main "$@"
