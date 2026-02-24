#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared constants, colours, logging and utility functions
# Sourced by all other library modules and by glados_installer.sh
# =============================================================================

# Guard: do not source more than once
[[ -n "${_GLADOS_COMMON_LOADED:-}" ]] && return 0
readonly _GLADOS_COMMON_LOADED=1

###############################################################################
# Global constants & defaults (CLI-overridable by the main script)
# shellcheck disable=SC2034   # Variables used by other sourced modules
###############################################################################

readonly INSTALLER_NAME="GLaDOS Installer"
readonly INSTALLER_VERSION="3.0.0"
readonly MIN_DISK_MB=15360           # 15 GB — extra room for audio/search containers
readonly MIN_RAM_MB=4096             # 4 GB minimum
readonly OLLAMA_HEALTH_TIMEOUT=30    # seconds
readonly OLLAMA_HEALTH_POLL=2        # seconds between API polls
readonly SEARXNG_HEALTH_TIMEOUT=60   # seconds
readonly SEARXNG_HEALTH_POLL=3       # seconds between health polls
readonly NETWORK_RETRY_COUNT=3
readonly NETWORK_RETRY_DELAY=5
readonly LOCK_FILE="${HOME}/.glados_installer.lock"
readonly MIN_CURL_VERSION="7.68.0"
readonly MIN_GIT_VERSION="2.25.0"
readonly MIN_DOCKER_VERSION="20.10.0"

# Whisper.cpp — model sizes: tiny, base, small (recommended for N4000), medium, large
readonly WHISPER_DEFAULT_MODEL="small"
readonly WHISPER_MODELS_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
readonly WHISPER_INSTALL_DIR="$HOME/.local/share/whisper.cpp"

# Piper TTS
readonly PIPER_INSTALL_DIR="$HOME/.local/share/piper"
readonly PIPER_BIN_DIR="$HOME/.local/bin"
readonly PIPER_RELEASES_URL="https://github.com/rhasspy/piper/releases/latest/download"
readonly PIPER_DEFAULT_VOICE="en_US-amy-medium"
PIPER_SELECTED_VOICE="${PIPER_DEFAULT_VOICE}"

# SearXNG web-search
readonly SEARXNG_COMPOSE_DIR="$HOME/glados-searxng"
readonly SEARXNG_PORT=8888

# Configurable via flags (defaults — overwritten by parse_args in main script)
OLLAMA_META_MODEL_TAG="${OLLAMA_META_MODEL_TAG:-llama3}"
GLADOS_AGENT_NAME="${GLADOS_AGENT_NAME:-GLaDOS}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
SKIP_TELEGRAM="${SKIP_TELEGRAM:-false}"
SKIP_AUDIO="${SKIP_AUDIO:-false}"
SKIP_INTERNET="${SKIP_INTERNET:-false}"
SKIP_STATIC_IP="${SKIP_STATIC_IP:-false}"
SKIP_SWAP="${SKIP_SWAP:-false}"
SKIP_FIREWALL="${SKIP_FIREWALL:-false}"
SKIP_HARDENING="${SKIP_HARDENING:-false}"
SKIP_HEALTHCHECK="${SKIP_HEALTHCHECK:-false}"
SKIP_GPU="${SKIP_GPU:-false}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
SHOW_STATUS="${SHOW_STATUS:-false}"
WHISPER_MODEL="${WHISPER_MODEL:-$WHISPER_DEFAULT_MODEL}"

# Swap configuration
SWAP_SIZE_MB="${SWAP_SIZE_MB:-auto}"        # "auto" = match RAM, cap 8 GB

# Firewall configuration
FIREWALL_SSH_PORT="${FIREWALL_SSH_PORT:-22}"

# Hardening configuration
GLADOS_HOSTNAME="${GLADOS_HOSTNAME:-}"          # empty = prompt or skip
GLADOS_TIMEZONE="${GLADOS_TIMEZONE:-}"          # empty = auto-detect / prompt
HARDEN_SSH="${HARDEN_SSH:-true}"

# Piper voice (selectable interactively or via CLI)
PIPER_VOICE="${PIPER_VOICE:-}"                  # empty = use PIPER_SELECTED_VOICE

# Proxy support (used by curl, apt, docker)
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"

# Telegram token (prefer: export TELEGRAM_BOT_TOKEN before running)
: "${TELEGRAM_BOT_TOKEN:=}"

# Progress tracking (global, incremented by each section call)
CURRENT_STEP=0
TOTAL_STEPS=10      # recalculated after arg parsing
INSTALL_START_EPOCH="${INSTALL_START_EPOCH:-}"

###############################################################################
# Logging root
###############################################################################

LOG_ROOT="$HOME/glados-installer"
LOG_DIR="$LOG_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_FILE:-$LOG_DIR/install_$(date '+%Y%m%d_%H%M%S').log}"

###############################################################################
# Colour palette (auto-disabled when stdout is not a TTY)
# shellcheck disable=SC2034   # Colours used by all sourced modules
###############################################################################

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

###############################################################################
# Logging helpers
###############################################################################

_strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

_log_raw() {
  local msg
  msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo -e "$msg" | _strip_ansi >>"$LOG_FILE"
  echo -e "$msg"
}

log()     { _log_raw "    $*"; }
debug()   { [[ "$VERBOSE" == true ]] && _log_raw "${DIM}DBG $*${NC}" || true; }
success() { _log_raw "${GREEN} ✔  $*${NC}"; }
warn()    { _log_raw "${YELLOW} ⚠  $*${NC}"; }
info()    { _log_raw "${CYAN} ℹ  $*${NC}"; }
fail()    { _log_raw "${RED} ✖  $*${NC}"; exit 1; }

###############################################################################
# Spinner — delegates to TUI library when loaded, fallback otherwise
###############################################################################

_SPINNER_PID=""

spinner_start() {
  local msg="${1:-Working...}"
  if declare -F tui_spinner_start >/dev/null 2>&1; then
    tui_spinner_start "$msg"
    return
  fi
  # Fallback (tui.sh not yet loaded)
  if [[ ! -t 1 ]]; then log "$msg"; return; fi
  (
    set +eEu; trap 'exit 0' TERM; trap '' ERR
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while true; do
      printf "\r  ${CYAN}%s${NC} %s " "${frames[$((i % ${#frames[@]}))]}" "$msg"
      i=$((i + 1)); sleep 0.12
    done
  ) &
  _SPINNER_PID=$!; disown "$_SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  if declare -F tui_spinner_stop >/dev/null 2>&1; then
    tui_spinner_stop
    return
  fi
  # Fallback
  if [[ -n "${_SPINNER_PID:-}" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
    kill "$_SPINNER_PID" 2>/dev/null || true
    wait "$_SPINNER_PID" 2>/dev/null || true
    printf "\r%80s\r" " "
  fi
  _SPINNER_PID=""
}

###############################################################################
# Elapsed time
###############################################################################

elapsed_time() {
  local start="${1:-${INSTALL_START_EPOCH:-}}"
  if [[ -z "$start" ]]; then
    printf '0m 00s'
    return
  fi
  local now
  now="$(date +%s)"
  local diff=$(( now - start ))
  printf '%dm %02ds' $((diff / 60)) $((diff % 60))
}

###############################################################################
# Section header — delegates to TUI when available
###############################################################################

section() {
  local title="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local step_label="${CURRENT_STEP}/${TOTAL_STEPS}"

  if declare -F tui_section >/dev/null 2>&1; then
    tui_section "$title" "$step_label"
  else
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  ${BOLD}[${step_label}]${NC} ${BLUE}${title}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi
}

###############################################################################
# Dry-run guard
###############################################################################

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    info "${DIM}[dry-run]${NC} $*"
    return 0
  fi
  debug "exec: $*"
  "$@"
}

###############################################################################
# Retry wrapper
###############################################################################

retry() {
  local description="$1"; shift
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ $attempt -ge $NETWORK_RETRY_COUNT ]]; then
      fail "${description}: failed after ${NETWORK_RETRY_COUNT} attempts."
    fi
    warn "${description}: attempt ${attempt}/${NETWORK_RETRY_COUNT} failed — retrying in ${NETWORK_RETRY_DELAY}s..."
    sleep "$NETWORK_RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

###############################################################################
# Secure download-and-run (downloads to tmp, validates, then executes)
###############################################################################

secure_download_and_run() {
  local url="$1"
  local description="${2:-install script}"
  shift 2
  local shell_args=("$@")

  local tmpfile
  tmpfile="$(mktemp "${TMPDIR:-/tmp}/glados_dl_XXXXXXXXXX")"

  curl -fsSL --connect-timeout 30 --max-time 300 "$url" -o "$tmpfile" \
    || { rm -f "$tmpfile"; fail "Failed to download ${description} from ${url}"; }

  if [[ ! -s "$tmpfile" ]]; then
    rm -f "$tmpfile"
    fail "Downloaded ${description} is empty (url: ${url})."
  fi

  local first_line
  first_line="$(head -1 "$tmpfile")"
  if [[ "$first_line" != *"#!/"* ]]; then
    warn "Downloaded ${description} does not start with a shebang — proceeding with caution."
  fi

  debug "Downloaded ${description}: $(wc -c < "$tmpfile") bytes."
  warn "No checksum/signature verification for ${description} — trust the source URL."

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Would execute downloaded ${description} ($(wc -c < "$tmpfile") bytes)."
    rm -f "$tmpfile"
    return 0
  fi

  # Use -e only: external scripts may reference unset variables
  bash --noprofile --norc -e "$tmpfile" "${shell_args[@]}"
  local rc=$?
  rm -f "$tmpfile"
  return $rc
}

###############################################################################
# Docker Compose command detection (v2: docker compose / v1: docker-compose)
###############################################################################

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    fail "Neither 'docker compose' (v2) nor 'docker-compose' (v1) is available."
  fi
}

###############################################################################
# PATH refresh & command check
###############################################################################

refresh_path() {
  # Only extend PATH — sourcing user profiles (.bashrc, .zshrc, etc.) is
  # intentionally avoided to prevent side effects in the installer context.
  export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
  hash -r 2>/dev/null || true
}

require_command() {
  local cmd="$1"
  local friendly="${2:-$1}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    debug "${cmd} not found — refreshing PATH..."
    refresh_path
  fi
  command -v "$cmd" >/dev/null 2>&1 \
    || fail "${friendly} not found on PATH after installation. Check your PATH and try again."
  debug "${cmd} → $(command -v "$cmd")"
}

###############################################################################
# Semver comparison (returns 0 if actual >= minimum)
###############################################################################

check_min_version() {
  local cmd="$1"
  local min_version="$2"
  local actual_version

  case "$cmd" in
    curl)   actual_version="$(curl --version 2>/dev/null | head -1 | awk '{print $2}')" ;;
    git)    actual_version="$(git --version 2>/dev/null | awk '{print $3}')" ;;
    docker) actual_version="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" ;;
    *)      debug "No version check for ${cmd}."; return 0 ;;
  esac

  [[ -z "$actual_version" ]] && { warn "Could not determine ${cmd} version."; return 0; }

  local lower
  lower="$(printf '%s\n%s' "$min_version" "$actual_version" | sort -V | head -1)"
  if [[ "$lower" != "$min_version" ]]; then
    warn "${cmd} ${actual_version} is older than recommended minimum ${min_version}."
    return 1
  fi
  debug "${cmd} ${actual_version} >= ${min_version} — OK."
  return 0
}

###############################################################################
# Interactive helpers
###############################################################################

confirm() {
  if declare -F tui_confirm >/dev/null 2>&1; then
    tui_confirm "$@"
    return $?
  fi
  # Fallback
  local prompt="$1"
  local default="${2:-y}"
  if [[ "$NON_INTERACTIVE" == true ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  local yn
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$(echo -e "${CYAN}? ${NC}${prompt} [${BOLD}Y${NC}/n]: ")" yn
      yn="${yn:-y}"
    else
      read -r -p "$(echo -e "${CYAN}? ${NC}${prompt} [y/${BOLD}N${NC}]: ")" yn
      yn="${yn:-n}"
    fi
    case "${yn,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "  Please answer y or n." ;;
    esac
  done
}

prompt_value() {
  if declare -F tui_input >/dev/null 2>&1; then
    tui_input "$1" "$2" "$3"
    return
  fi
  # Fallback
  local prompt="$1"
  local default="$2"
  local varname="$3"
  if [[ "$NON_INTERACTIVE" == true ]]; then
    printf -v "$varname" '%s' "$default"
    return
  fi
  local value
  read -r -p "$(echo -e "${CYAN}? ${NC}${prompt} [${DIM}${default}${NC}]: ")" value
  value="${value:-$default}"
  printf -v "$varname" '%s' "$value"
}

###############################################################################
# Lock file helpers
###############################################################################

LOCK_FD=""

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec {LOCK_FD}>"$LOCK_FILE"
    if ! flock -n "$LOCK_FD"; then
      fail "Another instance is already running. Remove ${LOCK_FILE} if stale."
    fi
    debug "Lock acquired via flock (fd=${LOCK_FD})."
  else
    if [[ -f "$LOCK_FILE" ]]; then
      local lock_pid
      lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo '')"
      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        fail "Another instance is running (PID ${lock_pid}). Remove ${LOCK_FILE} if stale."
      fi
      warn "Stale lock found — removing."
      rm -f "$LOCK_FILE"
    fi
    echo $$ >"$LOCK_FILE"
    debug "Lock acquired via PID file."
  fi
}

release_lock() {
  if [[ -n "${LOCK_FD:-}" ]]; then
    flock -u "$LOCK_FD" 2>/dev/null || true
    exec {LOCK_FD}>&- 2>/dev/null || true
  fi
  rm -f "$LOCK_FILE"
}
