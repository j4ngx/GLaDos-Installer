#!/usr/bin/env bash
# =============================================================================
# lib/preflight.sh — Pre-flight system checks
# =============================================================================

[[ -n "${_GLADOS_PREFLIGHT_LOADED:-}" ]] && return 0
readonly _GLADOS_PREFLIGHT_LOADED=1

preflight_checks() {
  section "Pre-flight system checks"

  # --- Architecture -----------------------------------------------------------
  local arch
  arch="$(uname -m)"
  log "Architecture: ${arch}"
  case "$arch" in
    x86_64|amd64)  debug "x86_64 — OK." ;;
    aarch64|arm64) debug "ARM64 — OK." ;;
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
    warn "Optimised for Debian — proceeding anyway."
  fi

  # --- Running user -----------------------------------------------------------
  if [[ "$(id -u)" -eq 0 ]]; then
    warn "Running as root. Recommended: regular user with sudo."
  fi
  command -v sudo >/dev/null 2>&1 \
    || fail "sudo is required. Install and configure sudo, then re-run."

  # --- RAM --------------------------------------------------------------------
  local ram_mb=0
  if [[ -f /proc/meminfo ]]; then
    ram_mb="$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo)"
  fi
  log "RAM: ${ram_mb} MB"
  if [[ "$ram_mb" -lt "$MIN_RAM_MB" ]]; then
    warn "Less than ${MIN_RAM_MB} MB RAM (${ram_mb} MB). Large models may be unstable."
  else
    success "RAM: ${ram_mb} MB ✔"
  fi

  # --- Disk space -------------------------------------------------------------
  local disk_avail_mb
  disk_avail_mb="$(df -BM "$HOME" | awk 'NR==2 {gsub(/M/, "", $4); print $4}')"
  log "Disk available (${HOME}): ${disk_avail_mb} MB"
  if [[ "$disk_avail_mb" -lt "$MIN_DISK_MB" ]]; then
    warn "Less than ${MIN_DISK_MB} MB free (${disk_avail_mb} MB). Models + search engine require space."
  else
    success "Disk: ${disk_avail_mb} MB free ✔"
  fi

  # --- CPU --------------------------------------------------------------------
  local cpu_model cpu_cores
  cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'Unknown')"
  cpu_cores="$(nproc 2>/dev/null || echo '?')"
  log "CPU: ${cpu_model} (${cpu_cores} cores)"
  if echo "$cpu_model" | grep -qi "N4000"; then
    info "Intel N4000 detected — whisper 'small' model recommended for voice."
  fi

  # --- Audio hardware ---------------------------------------------------------
  if command -v arecord >/dev/null 2>&1 || [[ -d /dev/snd ]]; then
    success "Audio device(s) detected."
  else
    warn "No ALSA audio devices found. Voice input will require a USB microphone."
  fi

  # --- Network ----------------------------------------------------------------
  spinner_start "Checking network connectivity..."
  if curl -sfm 10 https://ollama.com >/dev/null 2>&1; then
    spinner_stop
    success "Network: reachable (ollama.com)."
  else
    spinner_stop
    fail "Cannot reach https://ollama.com. Check your internet connection."
  fi

  # --- Dependency versions ----------------------------------------------------
  command -v curl >/dev/null 2>&1 || fail "curl is required but not installed."
  check_min_version curl "$MIN_CURL_VERSION" || true
  command -v git >/dev/null 2>&1 && check_min_version git "$MIN_GIT_VERSION" || true
}
