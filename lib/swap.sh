#!/usr/bin/env bash
# =============================================================================
# lib/swap.sh — Swap file configuration
#
# Creates or resizes a swap file to ensure the system has enough virtual
# memory for running LLMs.  Critical on machines with only 4-8 GB RAM.
#
# Default swap size: auto-calculated (= total RAM, capped at 8 GB).
# Idempotent: skips if a swap of the requested size already exists.
# =============================================================================

[[ -n "${_GLADOS_SWAP_LOADED:-}" ]] && return 0
readonly _GLADOS_SWAP_LOADED=1

# Defaults (overridable via CLI)
SWAP_SIZE_MB="${SWAP_SIZE_MB:-auto}"
SKIP_SWAP="${SKIP_SWAP:-false}"
readonly GLADOS_SWAP_FILE="/swapfile"

###############################################################################
# Auto-detect recommended swap size (MB)
###############################################################################

_recommended_swap_mb() {
  local ram_mb=0
  if [[ -f /proc/meminfo ]]; then
    ram_mb="$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo)"
  fi

  # Rule: match RAM size, cap at 8 GB
  local swap_mb="$ram_mb"
  (( swap_mb > 8192 )) && swap_mb=8192
  (( swap_mb < 2048 )) && swap_mb=2048
  echo "$swap_mb"
}

###############################################################################
# Current swap info
###############################################################################

_current_swap_mb() {
  awk '/^SwapTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

###############################################################################
# Main entry point
###############################################################################

configure_swap() {
  section "Swap file configuration"

  local current_swap
  current_swap="$(_current_swap_mb)"

  # Resolve target size
  local target_mb
  if [[ "$SWAP_SIZE_MB" == "auto" ]]; then
    target_mb="$(_recommended_swap_mb)"
  else
    target_mb="$SWAP_SIZE_MB"
  fi

  log "Current swap: ${current_swap} MB  ·  Target: ${target_mb} MB"

  # If existing swap is >= 90% of target, skip
  if (( current_swap >= (target_mb * 90 / 100) )); then
    success "Swap already adequate (${current_swap} MB >= ~${target_mb} MB)."
    return 0
  fi

  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo
    echo -e "  ${BOLD}Swap configuration${NC}"
    echo -e "  ─────────────────────────────────────────────────────"
    echo -e "  ${CYAN}Current swap :${NC} ${current_swap} MB"
    echo -e "  ${CYAN}Recommended  :${NC} ${target_mb} MB"
    echo -e "  ${CYAN}Swap file    :${NC} ${GLADOS_SWAP_FILE}"
    echo -e "  ─────────────────────────────────────────────────────"
    echo

    if ! confirm "Create/resize swap to ${target_mb} MB?" "y"; then
      info "Swap configuration skipped by user."
      return 0
    fi
  fi

  _create_swap_file "$target_mb"
}

###############################################################################
# Create / resize swap file
###############################################################################

_create_swap_file() {
  local size_mb="$1"

  # Disable existing swap on this file if active
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q "$GLADOS_SWAP_FILE"; then
    spinner_start "Disabling existing swap..."
    run_cmd sudo swapoff "$GLADOS_SWAP_FILE" 2>/dev/null || true
    spinner_stop
  fi

  spinner_start "Allocating ${size_mb} MB swap file (this may take a moment)..."
  # Detect filesystem — fallocate creates sparse/COW files on btrfs/zfs which
  # are incompatible with swap; fall back to dd on those filesystems.
  local fs_type
  fs_type="$(df --output=fstype "$(dirname "$GLADOS_SWAP_FILE")" 2>/dev/null | tail -1 | xargs)"
  if [[ "$fs_type" =~ ^(btrfs|zfs) ]]; then
    debug "Filesystem ${fs_type} detected — using dd (fallocate incompatible with swap)."
    run_cmd sudo dd if=/dev/zero of="$GLADOS_SWAP_FILE" bs=1M count="$size_mb" 2>/dev/null
  elif command -v fallocate >/dev/null 2>&1; then
    run_cmd sudo fallocate -l "${size_mb}M" "$GLADOS_SWAP_FILE"
  else
    run_cmd sudo dd if=/dev/zero of="$GLADOS_SWAP_FILE" bs=1M count="$size_mb" 2>/dev/null
  fi
  spinner_stop

  # Secure permissions (swap must be 600)
  run_cmd sudo chmod 600 "$GLADOS_SWAP_FILE"

  spinner_start "Formatting swap..."
  run_cmd sudo mkswap "$GLADOS_SWAP_FILE"
  spinner_stop

  spinner_start "Enabling swap..."
  run_cmd sudo swapon "$GLADOS_SWAP_FILE"
  spinner_stop

  # Make persistent in /etc/fstab
  if ! grep -q "$GLADOS_SWAP_FILE" /etc/fstab 2>/dev/null; then
    run_cmd sudo bash -c "echo '${GLADOS_SWAP_FILE} none swap sw 0 0' >> /etc/fstab"
    debug "Added swap entry to /etc/fstab."
  fi

  # Set swappiness to a reasonable value for LLM workloads
  local current_swappiness
  current_swappiness="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo '60')"
  if (( current_swappiness > 10 )); then
    run_cmd sudo sysctl -w vm.swappiness=10
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-glados.conf 2>/dev/null; then
      run_cmd sudo mkdir -p /etc/sysctl.d
      run_cmd sudo bash -c "echo 'vm.swappiness=10' >> /etc/sysctl.d/99-glados.conf"
    fi
    debug "Swappiness set to 10 (was ${current_swappiness})."
  fi

  local new_swap
  new_swap="$(_current_swap_mb)"
  success "Swap configured: ${new_swap} MB (file: ${GLADOS_SWAP_FILE})"
}

###############################################################################
# Health check
###############################################################################

check_swap_health() {
  local swap_mb
  swap_mb="$(_current_swap_mb)"
  if (( swap_mb > 0 )); then
    echo -e "  ${GREEN}✔${NC}  Swap            : ${swap_mb} MB"
    return 0
  else
    echo -e "  ${YELLOW}⚠${NC}  Swap            : none configured"
    return 1
  fi
}
