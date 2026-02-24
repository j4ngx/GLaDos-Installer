#!/usr/bin/env bash
# =============================================================================
# GLaDOS Installer
# =============================================================================
# Professional all-in-one installer for:
#   - Ollama + Meta Llama 3 (local LLM)
#   - OpenClaw (personal AI assistant)
#   - OpenClaw ↔ Ollama integration
#   - Optional Telegram channel (bot, e.g. "GLaDOS")
#
# Target: Debian 13 on low-power hardware (Intel N4000 / 8 GB RAM)
# Language: English only
#
# shellcheck disable=SC2034   # Allow unused colour variables for readability
# =============================================================================

set -Eeuo pipefail

###############################################################################
# Global constants & defaults (CLI-overridable)
###############################################################################

readonly INSTALLER_NAME="GLaDOS Installer"
readonly INSTALLER_VERSION="2.0.0"
readonly MIN_DISK_MB=10240          # 10 GB minimum free disk
readonly MIN_RAM_MB=4096            # 4 GB minimum RAM
readonly OLLAMA_HEALTH_TIMEOUT=30   # seconds to wait for Ollama API
readonly NETWORK_RETRY_COUNT=3      # retries for curl downloads
readonly NETWORK_RETRY_DELAY=5      # seconds between retries
readonly LOCK_FILE="/tmp/glados_installer.lock"
readonly MIN_CURL_VERSION="7.68.0"      # curl with --connect-timeout
readonly MIN_GIT_VERSION="2.25.0"       # modern git features
readonly MIN_DOCKER_VERSION="20.10.0"   # compose v2 support

# Configurable via flags
OLLAMA_META_MODEL_TAG="llama3"
GLADOS_AGENT_NAME="GLaDOS"
NON_INTERACTIVE=false
SKIP_TELEGRAM=false
SKIP_ONBOARD=false
DRY_RUN=false
VERBOSE=false
SHOW_STATUS=false

# Telegram token (prefer: export TELEGRAM_BOT_TOKEN before running)
: "${TELEGRAM_BOT_TOKEN:=}"

# Progress tracking
CURRENT_STEP=0
TOTAL_STEPS=8   # updated dynamically after arg parsing
INSTALL_START_EPOCH=""

###############################################################################
# Colour palette (auto-disabled when stdout is not a TTY)
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
# Logging
###############################################################################

LOG_ROOT="$HOME/glados-installer"
LOG_DIR="$LOG_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install_$(date '+%Y%m%d_%H%M%S').log"

# Strip ANSI codes when writing to the log file
_strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

_log_raw() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo -e "$msg" | _strip_ansi >>"$LOG_FILE"
  echo -e "$msg"
}

log()      { _log_raw "    $*"; }
debug()    { [[ "$VERBOSE" == true ]] && _log_raw "${DIM}DBG $*${NC}" || true; }
success()  { _log_raw "${GREEN} ✔  $*${NC}"; }
warn()     { _log_raw "${YELLOW} ⚠  $*${NC}"; }
info()     { _log_raw "${CYAN} ℹ  $*${NC}"; }
fail()     { _log_raw "${RED} ✖  $*${NC}"; exit 1; }

###############################################################################
# Spinner for long-running operations
###############################################################################

_SPINNER_PID=""

spinner_start() {
  local msg="${1:-Working...}"
  if [[ ! -t 1 ]]; then
    log "$msg"
    return
  fi
  (
    # Disable strict mode inside spinner — this is a cosmetic subprocess
    set +eEu
    trap '' ERR
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while true; do
      printf "\r  ${CYAN}%s${NC} %s " "${frames[$((i % ${#frames[@]}))]}" "$msg"
      i=$((i + 1))
      sleep 0.12
    done
  ) &
  _SPINNER_PID=$!
  disown "$_SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  if [[ -n "${_SPINNER_PID:-}" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
    kill "$_SPINNER_PID" 2>/dev/null || true
    wait "$_SPINNER_PID" 2>/dev/null || true
    printf "\r%80s\r" " "   # clear the spinner line
  fi
  _SPINNER_PID=""
}

###############################################################################
# Elapsed time helper
###############################################################################

elapsed_time() {
  local start="${1:-$INSTALL_START_EPOCH}"
  local now
  now="$(date +%s)"
  local diff=$(( now - start ))
  printf '%dm %02ds' $((diff / 60)) $((diff % 60))
}

###############################################################################
# Section / step header with progress
###############################################################################

section() {
  local title="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local progress="[${CURRENT_STEP}/${TOTAL_STEPS}]"
  echo
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  ${BOLD}${progress}${NC} ${BLUE}${title}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

###############################################################################
# ASCII Art banner
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
           Local LLM  ·  OpenClaw  ·  Telegram

BANNER
  echo -e "${NC}"
  echo -e "  ${CYAN}${BOLD}${INSTALLER_NAME}${NC}  ${DIM}v${INSTALLER_VERSION}${NC}"
  echo
}

###############################################################################
# Usage / help
###############################################################################

print_usage() {
  cat <<USAGE
${BOLD}${INSTALLER_NAME}${NC} v${INSTALLER_VERSION}

${BOLD}USAGE${NC}
  $(basename "$0") [OPTIONS]

${BOLD}OPTIONS${NC}
  --model <tag>         Ollama model tag (default: ${OLLAMA_META_MODEL_TAG})
                        Examples: llama3, llama3.1:instruct, phi3:mini
  --agent-name <name>   OpenClaw agent label (default: ${GLADOS_AGENT_NAME})
  --non-interactive     Skip interactive prompts where possible
  --skip-telegram       Skip Telegram channel configuration
  --skip-onboard        Skip 'openclaw onboard' wizard (run manually later)
  --dry-run             Show what would be done without making changes
  --verbose             Enable debug-level output
  --status              Show current installation status and exit
  --help, -h            Show this help message and exit

${BOLD}ENVIRONMENT VARIABLES${NC}
  TELEGRAM_BOT_TOKEN    Telegram bot token (export before running)

${BOLD}EXAMPLES${NC}
  # Basic install with defaults
  $(basename "$0")

  # Custom model and Telegram
  export TELEGRAM_BOT_TOKEN="123456:ABCdef..."
  $(basename "$0") --model llama3 --agent-name GLaDOS

  # Preview without changes
  $(basename "$0") --dry-run --verbose

USAGE
}

###############################################################################
# CLI argument parsing
###############################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)
        shift
        [[ $# -gt 0 ]] || fail "--model requires a value."
        OLLAMA_META_MODEL_TAG="$1"
        ;;
      --agent-name)
        shift
        [[ $# -gt 0 ]] || fail "--agent-name requires a value."
        GLADOS_AGENT_NAME="$1"
        ;;
      --non-interactive)  NON_INTERACTIVE=true ;;
      --skip-telegram)    SKIP_TELEGRAM=true ;;
      --skip-onboard)     SKIP_ONBOARD=true ;;
      --dry-run)          DRY_RUN=true ;;
      --verbose)          VERBOSE=true ;;
      --status)           SHOW_STATUS=true ;;
      --help|-h)          print_usage; exit 0 ;;
      *)                  fail "Unknown argument: $1  (use --help for usage)" ;;
    esac
    shift
  done

  # Recalculate total steps based on flags
  TOTAL_STEPS=8
  [[ "$SKIP_ONBOARD"  == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
  [[ "$SKIP_TELEGRAM" == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))
}

###############################################################################
# Lock file — prevent concurrent runs (flock-based when available)
###############################################################################

LOCK_FD=""

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    # Prefer flock for atomic locking
    exec {LOCK_FD}>"$LOCK_FILE"
    if ! flock -n "$LOCK_FD"; then
      fail "Another instance is already running. Remove ${LOCK_FILE} if this is stale."
    fi
    debug "Lock acquired via flock (fd=${LOCK_FD})."
  else
    # Fallback: PID-based lock file
    if [[ -f "$LOCK_FILE" ]]; then
      local lock_pid
      lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo '')"
      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        fail "Another instance is already running (PID ${lock_pid}). Remove ${LOCK_FILE} if this is stale."
      fi
      warn "Stale lock file found. Removing."
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

###############################################################################
# Cleanup / trap handler
###############################################################################

cleanup() {
  local exit_code=$?
  spinner_stop
  release_lock

  if [[ $exit_code -ne 0 ]]; then
    echo
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  Installation failed (exit code ${exit_code}).${NC}"
    echo -e "${RED}  Log file: ${LOG_FILE}${NC}"
    echo -e "${RED}  You can safely re-run this installer to resume.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi
}

trap cleanup EXIT
trap 'fail "Interrupted by user (SIGINT)."' INT
trap 'fail "Terminated (SIGTERM)."' TERM

###############################################################################
# Retry wrapper for network operations
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

    warn "${description}: attempt ${attempt}/${NETWORK_RETRY_COUNT} failed. Retrying in ${NETWORK_RETRY_DELAY}s..."
    sleep "$NETWORK_RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

###############################################################################
# Secure download helper — downloads to temp file and validates before piping
###############################################################################

secure_download_and_run() {
  local url="$1"
  local description="${2:-install script}"
  shift 2
  # Remaining args are passed to the shell running the script
  local shell_args=("$@")

  local tmpfile
  tmpfile="$(mktemp "${TMPDIR:-/tmp}/glados_dl_XXXXXXXXXX")"

  # Download to temp file so we can validate before executing
  curl -fsSL --connect-timeout 30 --max-time 300 "$url" -o "$tmpfile" \
    || { rm -f "$tmpfile"; fail "Failed to download ${description} from ${url}"; }

  # Validate: not empty and looks like a shell script
  if [[ ! -s "$tmpfile" ]]; then
    rm -f "$tmpfile"
    fail "Downloaded ${description} is empty (url: ${url})."
  fi

  local first_line
  first_line="$(head -1 "$tmpfile")"
  if [[ "$first_line" != *"#!/"* ]] && [[ "$first_line" != *"#!"* ]]; then
    warn "Downloaded ${description} does not start with a shebang. Proceeding with caution."
  fi

  debug "Downloaded ${description}: $(wc -c < "$tmpfile") bytes."

  # Execute with pipefail for safety
  bash --noprofile --norc -euo pipefail "$tmpfile" "${shell_args[@]}"
  local rc=$?
  rm -f "$tmpfile"
  return $rc
}

###############################################################################
# Require a command on PATH — refreshes hash table and common paths
###############################################################################

refresh_path() {
  # Re-source profile files to pick up PATH changes from install scripts
  for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" \
           "$HOME/.zshrc" "$HOME/.local/bin" /etc/profile; do
    if [[ -f "$f" ]]; then
      # shellcheck disable=SC1090
      source "$f" 2>/dev/null || true
    fi
  done
  # Also add common install directories directly
  export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
  hash -r 2>/dev/null || true
}

require_command() {
  local cmd="$1"
  local friendly="${2:-$1}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    debug "${cmd} not found on PATH, refreshing..."
    refresh_path
  fi

  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "${friendly} is required but was not found on PATH after installation. Check your PATH and try again."
  fi

  debug "${cmd} found at: $(command -v "$cmd")"
}

###############################################################################
# Minimum dependency version check
###############################################################################

check_min_version() {
  local cmd="$1"
  local min_version="$2"
  local actual_version

  case "$cmd" in
    curl)
      actual_version="$(curl --version 2>/dev/null | head -1 | awk '{print $2}')" ;;
    git)
      actual_version="$(git --version 2>/dev/null | awk '{print $3}')" ;;
    docker)
      actual_version="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" ;;
    *)
      debug "No version check implemented for ${cmd}."
      return 0 ;;
  esac

  if [[ -z "$actual_version" ]]; then
    warn "Could not determine ${cmd} version."
    return 0
  fi

  # Sort-based version comparison (works for dotted version strings)
  local lower
  lower="$(printf '%s\n%s' "$min_version" "$actual_version" | sort -V | head -1)"
  if [[ "$lower" != "$min_version" ]]; then
    warn "${cmd} version ${actual_version} is older than recommended minimum ${min_version}."
    return 1
  fi

  debug "${cmd} version ${actual_version} >= ${min_version} — OK."
  return 0
}

###############################################################################
# Dry-run guard — wraps commands that modify the system
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
# Interactive helpers
###############################################################################

# Ask a yes/no question. Returns 0 for yes, 1 for no.
# In non-interactive mode returns the default ($2: y or n).
confirm() {
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

# Prompt for a value with a default.
# Uses printf -v instead of eval to avoid shell injection.
prompt_value() {
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
# Pre-flight checks
###############################################################################

preflight_checks() {
  section "Pre-flight system checks"

  # --- Architecture -----------------------------------------------------------
  local arch
  arch="$(uname -m)"
  log "Architecture: ${arch}"
  case "$arch" in
    x86_64|amd64)  debug "x86_64 architecture — OK." ;;
    aarch64|arm64) debug "ARM64 architecture — OK." ;;
    *)             warn "Unsupported architecture: ${arch}. Installation may fail." ;;
  esac

  # --- OS detection -----------------------------------------------------------
  local distro_desc="Unknown"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    distro_desc="${PRETTY_NAME:-Unknown}"
  elif command -v lsb_release >/dev/null 2>&1; then
    distro_desc="$(lsb_release -ds 2>/dev/null || echo 'Unknown')"
  fi
  log "OS: ${distro_desc}"

  if ! echo "$distro_desc" | grep -qi "debian"; then
    warn "This installer is optimised for Debian. Proceeding anyway."
  fi

  # --- Running user -----------------------------------------------------------
  if [[ "$(id -u)" -eq 0 ]]; then
    warn "Running as root. It is recommended to use a regular user with sudo."
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is required. Install and configure sudo, then re-run."
  fi

  # --- RAM --------------------------------------------------------------------
  local ram_mb
  ram_mb="$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  log "RAM: ${ram_mb} MB"
  if [[ "$ram_mb" -lt "$MIN_RAM_MB" ]]; then
    warn "Less than ${MIN_RAM_MB} MB RAM detected (${ram_mb} MB). Large models may be slow or unstable."
  else
    success "RAM: ${ram_mb} MB (minimum ${MIN_RAM_MB} MB)."
  fi

  # --- Disk space (home partition) --------------------------------------------
  local disk_avail_mb
  disk_avail_mb="$(df -BM "$HOME" | awk 'NR==2 {gsub(/M/, "", $4); print $4}')"
  log "Disk available (${HOME}): ${disk_avail_mb} MB"
  if [[ "$disk_avail_mb" -lt "$MIN_DISK_MB" ]]; then
    warn "Less than ${MIN_DISK_MB} MB free disk space (${disk_avail_mb} MB). Model downloads require significant space."
  else
    success "Disk: ${disk_avail_mb} MB free (minimum ${MIN_DISK_MB} MB)."
  fi

  # --- CPU info ---------------------------------------------------------------
  local cpu_model
  cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'Unknown')"
  local cpu_cores
  cpu_cores="$(nproc 2>/dev/null || echo '?')"
  log "CPU: ${cpu_model} (${cpu_cores} cores)"
  if echo "$cpu_model" | grep -qi "N4000"; then
    info "Intel N4000 detected — low-power mode recommendations apply."
  fi

  # --- Network connectivity ---------------------------------------------------
  spinner_start "Checking network connectivity..."
  if curl -sfm 10 https://ollama.com >/dev/null 2>&1; then
    spinner_stop
    success "Network: reachable (ollama.com)."
  else
    spinner_stop
    fail "Cannot reach https://ollama.com. Check your internet connection and try again."
  fi

  # --- Dependency version checks ----------------------------------------------
  if command -v curl >/dev/null 2>&1; then
    check_min_version curl "$MIN_CURL_VERSION" || true
  else
    fail "curl is required but not installed."
  fi

  if command -v git >/dev/null 2>&1; then
    check_min_version git "$MIN_GIT_VERSION" || true
  fi
}

###############################################################################
# Interactive configuration review
###############################################################################

interactive_review() {
  if [[ "$NON_INTERACTIVE" == true ]]; then
    return
  fi

  echo
  echo -e "  ${BOLD}Installation Plan${NC}"
  echo -e "  ────────────────────────────────────────────"
  echo -e "  ${CYAN}Model        :${NC} ${OLLAMA_META_MODEL_TAG}"
  echo -e "  ${CYAN}Agent name   :${NC} ${GLADOS_AGENT_NAME}"
  echo -e "  ${CYAN}Telegram     :${NC} $( [[ "$SKIP_TELEGRAM" == true ]] && echo 'skip' || echo 'configure' )"
  echo -e "  ${CYAN}Onboard      :${NC} $( [[ "$SKIP_ONBOARD"  == true ]] && echo 'skip' || echo 'run wizard' )"
  echo -e "  ${CYAN}Dry run      :${NC} ${DRY_RUN}"
  echo -e "  ${CYAN}Verbose      :${NC} ${VERBOSE}"
  echo -e "  ${CYAN}Log file     :${NC} ${LOG_FILE}"
  echo -e "  ────────────────────────────────────────────"
  echo

  # Allow user to customise the model interactively
  if confirm "Change the Ollama model? (current: ${OLLAMA_META_MODEL_TAG})" "n"; then
    prompt_value "Enter Ollama model tag" "$OLLAMA_META_MODEL_TAG" OLLAMA_META_MODEL_TAG
  fi

  if ! confirm "Proceed with installation?" "y"; then
    info "Installation cancelled by user."
    exit 0
  fi
}

###############################################################################
# Base system packages (APT)
###############################################################################

install_base_packages() {
  section "Installing base system packages"

  spinner_start "Updating APT package index..."
  run_cmd sudo apt-get update -qq
  spinner_stop
  success "APT index updated."

  local pkgs=(
    curl wget git ca-certificates gnupg lsb-release
    build-essential cmake libopenblas-dev jq
  )

  spinner_start "Installing packages: ${pkgs[*]}"
  run_cmd sudo apt-get install -y -qq "${pkgs[@]}"
  spinner_stop
  success "Base packages installed."
}

###############################################################################
# Docker
###############################################################################

install_docker_if_missing() {
  section "Docker runtime"

  if command -v docker >/dev/null 2>&1; then
    local docker_ver
    docker_ver="$(docker --version 2>/dev/null || echo 'unknown')"
    success "Docker already installed (${docker_ver})."
    return
  fi

  log "Docker not found — installing via official convenience script..."
  spinner_start "Installing Docker..."
  retry "Docker install" bash -c 'set -euo pipefail; curl -fsSL https://get.docker.com | sudo sh'
  spinner_stop

  run_cmd sudo systemctl enable --now docker
  run_cmd sudo usermod -aG docker "$USER" || true

  success "Docker installed."
  warn "You may need to log out and back in for the 'docker' group membership to take effect."
}

###############################################################################
# Ollama
###############################################################################

install_ollama() {
  section "Ollama installation"

  if command -v ollama >/dev/null 2>&1; then
    local ollama_ver
    ollama_ver="$(ollama --version 2>/dev/null || echo 'unknown')"
    success "Ollama already installed (${ollama_ver})."
  else
    spinner_start "Installing Ollama..."
    retry "Ollama install" secure_download_and_run "https://ollama.com/install.sh" "Ollama installer"
    spinner_stop
    success "Ollama installed."
    require_command ollama "Ollama CLI"
  fi

  # Enable systemd service if available
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q ollama; then
    log "Enabling Ollama systemd service..."
    run_cmd sudo systemctl enable --now ollama || true
  fi

  # Wait for Ollama API with timeout
  spinner_start "Waiting for Ollama API (max ${OLLAMA_HEALTH_TIMEOUT}s)..."
  local waited=0
  while [[ $waited -lt $OLLAMA_HEALTH_TIMEOUT ]]; do
    if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
      spinner_stop
      success "Ollama API is responding on http://127.0.0.1:11434."
      return
    fi
    sleep 2
    waited=$((waited + 2))
  done
  spinner_stop
  warn "Ollama API did not respond within ${OLLAMA_HEALTH_TIMEOUT}s. Check 'journalctl -u ollama' for details."
}

###############################################################################
# Pull Ollama model
###############################################################################

pull_ollama_model() {
  section "Pulling Ollama model: ${OLLAMA_META_MODEL_TAG}"

  # Check if model is already available locally
  if ollama list 2>/dev/null | grep -q "${OLLAMA_META_MODEL_TAG}"; then
    success "Model '${OLLAMA_META_MODEL_TAG}' is already available locally."
    return
  fi

  log "Downloading model '${OLLAMA_META_MODEL_TAG}' — this may take a while on slow connections..."
  retry "Ollama model pull" ollama pull "${OLLAMA_META_MODEL_TAG}"
  success "Model '${OLLAMA_META_MODEL_TAG}' downloaded successfully."
}

###############################################################################
# OpenClaw
###############################################################################

install_openclaw() {
  section "OpenClaw installation"

  if command -v openclaw >/dev/null 2>&1; then
    local oc_ver
    oc_ver="$(openclaw --version 2>/dev/null || echo 'unknown')"
    success "OpenClaw already installed (${oc_ver})."
    return
  fi

  spinner_start "Installing OpenClaw..."
  retry "OpenClaw install" secure_download_and_run "https://openclaw.ai/install.sh" "OpenClaw installer" --no-onboard
  spinner_stop
  success "OpenClaw CLI installed."

  # Refresh PATH so subsequent openclaw calls work in this session
  require_command openclaw "OpenClaw CLI"
}

###############################################################################
# OpenClaw onboarding wizard
###############################################################################

run_openclaw_onboard() {
  section "OpenClaw onboarding wizard"

  require_command openclaw "OpenClaw CLI"

  echo
  echo -e "  ${BOLD}The onboarding wizard will:${NC}"
  echo -e "    • Configure authentication and security"
  echo -e "    • Set up the local gateway (ports, binding)"
  echo -e "    • Optionally install the background daemon"
  echo -e "    • Optionally connect communication channels"
  echo
  echo -e "  ${BOLD}Recommended choices:${NC}"
  echo -e "    • Use local mode"
  echo -e "    • Bind gateway to ${BOLD}127.0.0.1${NC} for security"
  echo -e "    • Accept daemon installation"
  echo
  echo -e "  ${DIM}Re-run any time with: openclaw onboard --install-daemon${NC}"
  echo

  if [[ "$NON_INTERACTIVE" == true ]]; then
    warn "Non-interactive mode active — but the onboard wizard is inherently interactive."
    warn "You must answer its prompts."
  fi

  run_cmd openclaw onboard --install-daemon
  success "OpenClaw onboarding completed."
}

###############################################################################
# Wire OpenClaw ↔ Ollama
###############################################################################

configure_openclaw_ollama() {
  section "Configuring OpenClaw ↔ Ollama integration"

  require_command openclaw "OpenClaw CLI"

  # Register Ollama provider (dummy API key — Ollama doesn't need a real one)
  run_cmd openclaw config set models.providers.ollama.apiKey "ollama-local"

  # Set default model
  run_cmd openclaw config set agents.defaults.model.primary "ollama/${OLLAMA_META_MODEL_TAG}"

  # Set agent label
  run_cmd openclaw config set agents.defaults.label "${GLADOS_AGENT_NAME}" || true

  success "Default model set to 'ollama/${OLLAMA_META_MODEL_TAG}' (agent: ${GLADOS_AGENT_NAME})."
}

###############################################################################
# Telegram channel
###############################################################################

configure_openclaw_telegram() {
  section "Telegram channel configuration"

  require_command openclaw "OpenClaw CLI"

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo
    info "TELEGRAM_BOT_TOKEN is not set in the environment."
    info "You need a token from @BotFather on Telegram."

    if [[ "$NON_INTERACTIVE" == true ]]; then
      warn "Non-interactive mode — cannot prompt for Telegram token. Skipping."
      return
    fi

    echo
    read -r -s -p "$(echo -e "${CYAN}? ${NC}Paste your Telegram bot token (hidden): ")" TELEGRAM_BOT_TOKEN
    echo
  fi

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    warn "No Telegram token provided. Skipping Telegram setup."
    return
  fi

  # Basic format validation (numeric_id:alphanum_token)
  if ! [[ "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    warn "Telegram token format looks invalid. Expected '<id>:<hash>'."
    if ! confirm "Continue anyway?" "n"; then
      warn "Telegram setup cancelled."
      return
    fi
  fi

  log "Configuring Telegram channel (token is not logged for security)."
  run_cmd openclaw config set channels.telegram.enabled true
  run_cmd openclaw config set channels.telegram.botToken "${TELEGRAM_BOT_TOKEN}"
  run_cmd openclaw config set channels.telegram.dmPolicy "pairing"

  success "Telegram channel configured."

  # Security: clear token from memory now that it has been persisted to config
  unset TELEGRAM_BOT_TOKEN
  debug "TELEGRAM_BOT_TOKEN cleared from process environment."

  echo
  echo -e "  ${BOLD}Next steps for Telegram:${NC}"
  echo -e "    1. Open a chat with your bot in Telegram and send \"hi\"."
  echo -e "    2. List pending pairing requests:"
  echo -e "         ${DIM}openclaw pairing list telegram${NC}"
  echo -e "    3. Approve the pairing:"
  echo -e "         ${DIM}openclaw pairing approve telegram <CODE>${NC}"
  echo -e "    4. Start chatting with your assistant from Telegram."
  echo
}

###############################################################################
# Post-install health verification
###############################################################################

run_health_check() {
  echo
  echo -e "  ${BOLD}Post-install health check${NC}"
  echo -e "  ────────────────────────────────────────────"

  local all_ok=true

  # Ollama API
  if curl -sfm 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Ollama API           : reachable"
  else
    echo -e "  ${RED}✖${NC}  Ollama API           : unreachable"
    all_ok=false
  fi

  # Ollama model
  if ollama list 2>/dev/null | grep -q "${OLLAMA_META_MODEL_TAG}"; then
    echo -e "  ${GREEN}✔${NC}  Ollama model         : ${OLLAMA_META_MODEL_TAG}"
  else
    echo -e "  ${RED}✖${NC}  Ollama model         : ${OLLAMA_META_MODEL_TAG} not found"
    all_ok=false
  fi

  # OpenClaw CLI
  if command -v openclaw >/dev/null 2>&1; then
    local oc_ver
    oc_ver="$(openclaw --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  OpenClaw CLI         : ${oc_ver}"
  else
    echo -e "  ${RED}✖${NC}  OpenClaw CLI         : not found"
    all_ok=false
  fi

  # OpenClaw gateway / daemon
  if command -v openclaw >/dev/null 2>&1; then
    if openclaw gateway status >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔${NC}  OpenClaw gateway     : running"
    else
      echo -e "  ${YELLOW}⚠${NC}  OpenClaw gateway     : not running (start with: openclaw gateway start)"
    fi
  fi

  # Docker
  if command -v docker >/dev/null 2>&1; then
    local docker_ver
    docker_ver="$(docker --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  Docker               : ${docker_ver}"
  else
    echo -e "  ${YELLOW}⚠${NC}  Docker               : not found"
  fi

  echo -e "  ────────────────────────────────────────────"

  if [[ "$all_ok" == true ]]; then
    success "All health checks passed."
  else
    warn "Some health checks failed. Review the output above."
  fi
}

###############################################################################
# Summary
###############################################################################

print_summary() {
  local elapsed
  elapsed="$(elapsed_time "$INSTALL_START_EPOCH")"

  echo
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ${BOLD}GLaDOS environment is ready!${NC}  ${DIM}(${elapsed})${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${BOLD}Installed components:${NC}"
  echo -e "    • Ollama (local LLM runtime)"
  echo -e "    • Model: ${CYAN}${OLLAMA_META_MODEL_TAG}${NC}"
  echo -e "    • OpenClaw CLI + gateway"
  echo -e "    • Agent: ${CYAN}${GLADOS_AGENT_NAME}${NC} → ollama/${OLLAMA_META_MODEL_TAG}"
  if [[ "$SKIP_TELEGRAM" != true ]]; then
    echo -e "    • Telegram channel (pending pairing)"
  fi
  echo
  echo -e "  ${BOLD}Quick reference:${NC}"
  echo -e "    ${DIM}# Ollama${NC}"
  echo -e "    ollama list"
  echo -e "    curl http://127.0.0.1:11434/api/tags"
  echo
  echo -e "    ${DIM}# OpenClaw${NC}"
  echo -e "    openclaw status"
  echo -e "    openclaw gateway status"
  echo -e "    openclaw health"
  echo -e "    openclaw dashboard        ${DIM}# opens http://127.0.0.1:18789/${NC}"
  echo
  if [[ "$SKIP_TELEGRAM" != true ]]; then
    echo -e "    ${DIM}# Telegram pairing${NC}"
    echo -e "    openclaw channels status"
    echo -e "    openclaw pairing list telegram"
    echo -e "    openclaw pairing approve telegram <CODE>"
    echo
  fi
  echo -e "    ${DIM}# Change default model${NC}"
  echo -e "    ollama pull phi3:mini"
  echo -e "    openclaw config set agents.defaults.model.primary \"ollama/phi3:mini\""
  echo
  echo -e "  ${BOLD}Log file:${NC} ${DIM}${LOG_FILE}${NC}"
  echo

  run_health_check
  echo
  success "All ${TOTAL_STEPS} steps completed in ${elapsed}."
}

###############################################################################
# Status command (--status) — quick health overview without installing
###############################################################################

show_status() {
  print_banner
  echo -e "  ${BOLD}GLaDOS Environment Status${NC}"
  echo -e "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  local component status_icon version_info

  # Ollama CLI
  if command -v ollama >/dev/null 2>&1; then
    version_info="$(ollama --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  Ollama CLI         : ${version_info}"
  else
    echo -e "  ${RED}✖${NC}  Ollama CLI         : not installed"
  fi

  # Ollama API
  if curl -sfm 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Ollama API         : reachable (127.0.0.1:11434)"
    # List models
    local models
    models="$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | paste -sd', ' || echo 'none')"
    echo -e "  ${CYAN}ℹ${NC}  Ollama models      : ${models:-none}"
  else
    echo -e "  ${RED}✖${NC}  Ollama API         : unreachable"
  fi

  # OpenClaw CLI
  if command -v openclaw >/dev/null 2>&1; then
    version_info="$(openclaw --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  OpenClaw CLI       : ${version_info}"
    # Gateway
    if openclaw gateway status >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔${NC}  OpenClaw gateway   : running"
    else
      echo -e "  ${YELLOW}⚠${NC}  OpenClaw gateway   : not running"
    fi
  else
    echo -e "  ${RED}✖${NC}  OpenClaw CLI       : not installed"
  fi

  # Docker
  if command -v docker >/dev/null 2>&1; then
    version_info="$(docker --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  Docker             : ${version_info}"
  else
    echo -e "  ${YELLOW}⚠${NC}  Docker             : not installed"
  fi

  echo
  echo -e "  ${BOLD}Log directory:${NC} ${DIM}${LOG_DIR}${NC}"
  echo
}

###############################################################################
# Main entry point
###############################################################################

main() {
  INSTALL_START_EPOCH="$(date +%s)"

  print_banner
  parse_args "$@"

  # --status: show current state and exit (no lock needed)
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

  if [[ "$SKIP_ONBOARD" != true ]]; then
    run_openclaw_onboard
  fi

  configure_openclaw_ollama

  if [[ "$SKIP_TELEGRAM" != true ]]; then
    configure_openclaw_telegram
  fi

  print_summary
}

main "$@"
