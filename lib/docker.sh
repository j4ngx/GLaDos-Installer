#!/usr/bin/env bash
# =============================================================================
# lib/docker.sh — Docker runtime installation
# =============================================================================

[[ -n "${_GLADOS_DOCKER_LOADED:-}" ]] && return 0
readonly _GLADOS_DOCKER_LOADED=1

install_docker_if_missing() {
  section "Docker runtime"

  if command -v docker >/dev/null 2>&1; then
    local docker_ver
    docker_ver="$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    check_min_version docker "$MIN_DOCKER_VERSION" || true
    success "Docker already installed (${docker_ver})."
    _ensure_docker_group
    return
  fi

  log "Docker not found — installing via official convenience script..."
  spinner_start "Installing Docker..."
  # Download and validate the script before executing (shebang + empty check).
  # Docker install requires root — wrap the execution with sudo.
  local tmpfile
  tmpfile="$(mktemp "${TMPDIR:-/tmp}/glados_docker_XXXXXXXXXX")"
  retry "Docker download" \
    curl -fsSL --connect-timeout 30 --max-time 300 "https://get.docker.com" -o "$tmpfile"
  if [[ ! -s "$tmpfile" ]]; then
    rm -f "$tmpfile"
    fail "Downloaded Docker installer is empty."
  fi
  local first_line
  first_line="$(head -1 "$tmpfile")"
  if [[ "$first_line" != *"#!/"* ]]; then
    warn "Docker installer does not start with a shebang — proceeding with caution."
  fi
  debug "Docker installer downloaded: $(wc -c < "$tmpfile") bytes."
  # Use -eu without pipefail: external installer scripts may not be pipefail-safe
  sudo bash --noprofile --norc -eu "$tmpfile"
  rm -f "$tmpfile"
  spinner_stop

  run_cmd sudo systemctl enable --now docker
  _ensure_docker_group

  success "Docker installed."
  warn "Log out and back in for the 'docker' group to take effect (or run: newgrp docker)."
}

_ensure_docker_group() {
  if ! groups "$USER" 2>/dev/null | grep -qw docker; then
    run_cmd sudo usermod -aG docker "$USER" || true
    debug "Added ${USER} to docker group."
  fi
}
