#!/usr/bin/env bash
# =============================================================================
# lib/ollama.sh — Ollama LLM runtime installation and model management
# =============================================================================

[[ -n "${_GLADOS_OLLAMA_LOADED:-}" ]] && return 0
readonly _GLADOS_OLLAMA_LOADED=1

install_ollama() {
  section "Ollama installation"

  if command -v ollama >/dev/null 2>&1; then
    local ollama_ver
    ollama_ver="$(ollama --version 2>/dev/null || echo 'unknown')"
    success "Ollama already installed (${ollama_ver})."
  else
    spinner_start "Installing Ollama..."
    retry "Ollama install" \
      secure_download_and_run "https://ollama.com/install.sh" "Ollama installer"
    spinner_stop
    success "Ollama installed."
    require_command ollama "Ollama CLI"
  fi

  # Enable / start systemd service if available
  if command -v systemctl >/dev/null 2>&1 \
      && systemctl list-unit-files 2>/dev/null | grep -q ollama; then
    log "Enabling Ollama systemd service..."
    run_cmd sudo systemctl enable --now ollama || true
  fi

  _wait_for_ollama_api || warn "Ollama API may not be ready — continuing anyway."
}

_wait_for_ollama_api() {
  spinner_start "Waiting for Ollama API (max ${OLLAMA_HEALTH_TIMEOUT}s)..."
  local waited=0
  while [[ $waited -lt $OLLAMA_HEALTH_TIMEOUT ]]; do
    if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
      spinner_stop
      success "Ollama API responding on http://127.0.0.1:11434 ✔"
      return 0
    fi
    sleep "$OLLAMA_HEALTH_POLL"
    waited=$((waited + OLLAMA_HEALTH_POLL))
  done
  spinner_stop
  warn "Ollama API did not respond within ${OLLAMA_HEALTH_TIMEOUT}s. Check: journalctl -u ollama"
  return 1
}

pull_ollama_model() {
  section "Pulling Ollama model: ${OLLAMA_META_MODEL_TAG}"

  # Normalise tag for matching: 'model' matches 'model:latest', 'model:tag' matches exact
  local match_tag="$OLLAMA_META_MODEL_TAG"
  if [[ "$match_tag" != *:* ]]; then
    match_tag="${match_tag}:latest"
  fi

  if ollama list 2>/dev/null | awk '{print $1}' | grep -qxF "$match_tag"; then
    success "Model '${OLLAMA_META_MODEL_TAG}' already available locally."
    return
  fi

  log "Downloading '${OLLAMA_META_MODEL_TAG}' — this may take several minutes on slow connections..."
  retry "Ollama model pull" run_cmd ollama pull "${OLLAMA_META_MODEL_TAG}"
  success "Model '${OLLAMA_META_MODEL_TAG}' downloaded ✔"
}

# Health helper used by the main summary
check_ollama_health() {
  local ok=true

  if curl -sfm 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  Ollama API      : reachable"
  else
    echo -e "  ${RED}✖${NC}  Ollama API      : unreachable"
    ok=false
  fi

  # Normalise tag for matching: 'model' matches 'model:latest', 'model:tag' matches exact
  local health_match_tag="$OLLAMA_META_MODEL_TAG"
  if [[ "$health_match_tag" != *:* ]]; then
    health_match_tag="${health_match_tag}:latest"
  fi

  if ollama list 2>/dev/null | awk '{print $1}' | grep -qxF "$health_match_tag"; then
    echo -e "  ${GREEN}✔${NC}  Ollama model    : ${OLLAMA_META_MODEL_TAG}"
  else
    echo -e "  ${RED}✖${NC}  Ollama model    : ${OLLAMA_META_MODEL_TAG} (missing)"
    ok=false
  fi

  [[ "$ok" == true ]]
}
