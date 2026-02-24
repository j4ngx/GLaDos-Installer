#!/usr/bin/env bash
# =============================================================================
# lib/gpu.sh — GPU detection and Ollama acceleration configuration
#
# Auto-detects NVIDIA or AMD GPUs and configures the environment so that
# Ollama can leverage GPU acceleration (CUDA / ROCm).
#
# On systems without a discrete GPU (e.g. Intel N4000), this step simply
# reports "CPU only" and skips — no packages are installed.
# =============================================================================

[[ -n "${_GLADOS_GPU_LOADED:-}" ]] && return 0
readonly _GLADOS_GPU_LOADED=1

SKIP_GPU="${SKIP_GPU:-false}"
DETECTED_GPU="none"

###############################################################################
# Main entry point
###############################################################################

configure_gpu() {
  section "GPU detection & acceleration"

  if [[ "$SKIP_GPU" == true ]]; then
    info "GPU detection skipped (--skip-gpu)."
    return 0
  fi

  _detect_gpu

  case "$DETECTED_GPU" in
    nvidia) _configure_nvidia ;;
    amd)    _configure_amd ;;
    none)
      info "No discrete GPU detected — Ollama will use CPU only."
      info "This is normal for Intel N4000 and similar low-power hardware."
      ;;
  esac
}

###############################################################################
# GPU detection
###############################################################################

_detect_gpu() {
  spinner_start "Scanning for GPUs..."

  # Check for NVIDIA
  if lspci 2>/dev/null | grep -iq "nvidia"; then
    DETECTED_GPU="nvidia"
    local gpu_name
    gpu_name="$(lspci 2>/dev/null | grep -i 'nvidia' | head -1 | sed 's/.*: //')"
    spinner_stop
    success "NVIDIA GPU detected: ${gpu_name}"
    return 0
  fi

  # Check for AMD Radeon
  if lspci 2>/dev/null | grep -iq "AMD.*Radeon\|AMD.*RX\|AMD.*Vega"; then
    DETECTED_GPU="amd"
    local gpu_name
    gpu_name="$(lspci 2>/dev/null | grep -i 'AMD' | grep -i 'VGA\|Display\|3D' | head -1 | sed 's/.*: //')"
    spinner_stop
    success "AMD GPU detected: ${gpu_name}"
    return 0
  fi

  # Check via /dev nodes
  if [[ -e /dev/nvidia0 ]]; then
    DETECTED_GPU="nvidia"
    spinner_stop
    success "NVIDIA GPU detected (via /dev/nvidia0)."
    return 0
  fi

  if [[ -d /dev/dri/renderD128 ]] && (lspci 2>/dev/null | grep -iq "AMD"); then
    DETECTED_GPU="amd"
    spinner_stop
    success "AMD GPU detected (via DRI render node)."
    return 0
  fi

  spinner_stop
  debug "No discrete NVIDIA/AMD GPU found."
}

###############################################################################
# NVIDIA configuration
###############################################################################

_configure_nvidia() {
  info "Configuring NVIDIA GPU acceleration for Ollama..."

  # Check if nvidia-smi is available
  if command -v nvidia-smi >/dev/null 2>&1; then
    local driver_ver
    driver_ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
    local gpu_mem
    gpu_mem="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)"
    success "NVIDIA driver: ${driver_ver}  VRAM: ${gpu_mem}"
  else
    warn "NVIDIA GPU found but nvidia-smi not available."
    echo
    echo -e "  ${BOLD}To enable GPU acceleration:${NC}"
    echo -e "    1. Install NVIDIA drivers:"
    echo -e "       ${DIM}sudo apt-get install -y nvidia-driver${NC}"
    echo -e "    2. Reboot the system"
    echo -e "    3. Re-run this installer"
    echo

    if [[ "$NON_INTERACTIVE" != true ]]; then
      if confirm "Install NVIDIA driver now? (requires reboot)" "n"; then
        spinner_start "Installing NVIDIA driver..."
        run_cmd sudo apt-get install -y -qq nvidia-driver
        spinner_stop
        warn "NVIDIA driver installed. You MUST reboot before GPU will be available."
        warn "After reboot, re-run this installer to enable GPU acceleration."
      fi
    fi
    return 0
  fi

  # Check for NVIDIA Container Toolkit (needed for Docker + GPU)
  if ! command -v nvidia-container-cli >/dev/null 2>&1; then
    info "Installing NVIDIA Container Toolkit (for Docker GPU access)..."
    if curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
         | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
      curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
      run_cmd sudo apt-get update -qq
      run_cmd sudo apt-get install -y -qq nvidia-container-toolkit
      run_cmd sudo nvidia-ctk runtime configure --runtime=docker
      run_cmd sudo systemctl restart docker 2>/dev/null || true
      success "NVIDIA Container Toolkit installed."
    else
      warn "Failed to install NVIDIA Container Toolkit — Docker GPU passthrough may not work."
    fi
  else
    success "NVIDIA Container Toolkit already installed."
  fi

  # Ollama should auto-detect NVIDIA; verify
  info "Ollama will auto-detect NVIDIA GPU on next restart."
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ollama 2>/dev/null; then
    run_cmd sudo systemctl restart ollama
    debug "Ollama service restarted to pick up GPU."
  fi
}

###############################################################################
# AMD configuration
###############################################################################

_configure_amd() {
  info "Configuring AMD GPU acceleration for Ollama..."

  # Check for ROCm
  if command -v rocm-smi >/dev/null 2>&1; then
    local rocm_ver
    rocm_ver="$(rocm-smi --showdriverversion 2>/dev/null | grep -oP 'Driver version:\s*\K[\d.]+' || echo 'unknown')"
    success "ROCm driver detected: ${rocm_ver}"
  else
    warn "AMD GPU found but ROCm is not installed."
    echo
    echo -e "  ${BOLD}To enable GPU acceleration:${NC}"
    echo -e "    1. Install ROCm:"
    echo -e "       ${DIM}See https://rocm.docs.amd.com/projects/install-on-linux/${NC}"
    echo -e "    2. Reboot the system"
    echo -e "    3. Re-run this installer"
    echo
    return 0
  fi

  # Ensure user is in render/video groups
  for grp in render video; do
    if getent group "$grp" >/dev/null 2>&1; then
      if ! groups "$USER" 2>/dev/null | grep -qw "$grp"; then
        run_cmd sudo usermod -aG "$grp" "$USER"
        debug "Added ${USER} to ${grp} group."
      fi
    fi
  done

  info "Ollama will auto-detect AMD GPU with ROCm on next restart."
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ollama 2>/dev/null; then
    run_cmd sudo systemctl restart ollama
    debug "Ollama service restarted to pick up GPU."
  fi
}

###############################################################################
# Health check
###############################################################################

check_gpu_health() {
  # NVIDIA
  if command -v nvidia-smi >/dev/null 2>&1; then
    local gpu_info
    gpu_info="$(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null | head -1)"
    echo -e "  ${GREEN}✔${NC}  GPU (NVIDIA)    : ${gpu_info}"
    return 0
  fi

  # AMD
  if command -v rocm-smi >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  GPU (AMD/ROCm)  : available"
    return 0
  fi

  echo -e "  ${DIM}  GPU             : CPU only${NC}"
  return 0
}
