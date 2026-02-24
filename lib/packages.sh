#!/usr/bin/env bash
# =============================================================================
# lib/packages.sh — Base APT system packages
# =============================================================================

[[ -n "${_GLADOS_PACKAGES_LOADED:-}" ]] && return 0
readonly _GLADOS_PACKAGES_LOADED=1

install_base_packages() {
  section "Installing base system packages"

  spinner_start "Updating APT package index..."
  run_cmd sudo apt-get update -qq
  spinner_stop
  success "APT index updated."

  local pkgs=(
    # Core utilities
    curl wget git ca-certificates gnupg lsb-release jq
    # Build tools (needed for whisper.cpp)
    build-essential cmake pkg-config
    # BLAS/lapack acceleration for Whisper
    libopenblas-dev liblapack-dev
    # Audio stack
    alsa-utils sox libsox-fmt-all portaudio19-dev
    # Python is needed for helper tooling; keep it minimal
    python3 python3-pip python3-venv
    # ffmpeg — audio/video processing (Whisper input conversion)
    ffmpeg
    # Misc
    unzip tar
  )

  spinner_start "Installing packages (${#pkgs[@]} items)..."
  run_cmd sudo apt-get install -y -qq "${pkgs[@]}"
  spinner_stop
  success "Base packages installed."
}
