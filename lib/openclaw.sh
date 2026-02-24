#!/usr/bin/env bash
# =============================================================================
# lib/openclaw.sh — OpenClaw CLI: installation, onboarding and model config
# =============================================================================

[[ -n "${_GLADOS_OPENCLAW_LOADED:-}" ]] && return 0
readonly _GLADOS_OPENCLAW_LOADED=1

# ---------------------------------------------------------------------------
# Quiet config setter — suppresses OpenClaw's verbose banners & SHA diffs.
# Output is logged to LOG_FILE; errors are surfaced normally.
# ---------------------------------------------------------------------------
oc_config_set() {
  if [[ "$DRY_RUN" == true ]]; then
    info "${DIM}[dry-run]${NC} openclaw config set $*"
    return 0
  fi
  local out
  debug "exec: openclaw config set $*"
  if ! out=$(openclaw config set "$@" 2>&1); then
    warn "openclaw config set $* — failed"
    echo "$out" | _strip_ansi >> "$LOG_FILE"
    return 1
  fi
  echo "$out" | _strip_ansi >> "$LOG_FILE"
}

install_openclaw() {
  section "OpenClaw installation"

  if command -v openclaw >/dev/null 2>&1; then
    local oc_ver
    oc_ver="$(openclaw --version 2>/dev/null || echo 'unknown')"
    success "OpenClaw already installed (${oc_ver})."
    return
  fi

  spinner_start "Installing OpenClaw..."
  retry "OpenClaw install" \
    secure_download_and_run "https://openclaw.ai/install.sh" "OpenClaw installer" --no-onboard
  spinner_stop
  success "OpenClaw CLI installed."
  require_command openclaw "OpenClaw CLI"
}

run_openclaw_onboard() {
  section "OpenClaw gateway & daemon setup"
  require_command openclaw "OpenClaw CLI"

  # Idempotent: skip if gateway is already up
  if openclaw gateway status >/dev/null 2>&1; then
    success "OpenClaw gateway already running — skipping setup."
    return
  fi

  # Bind gateway to loopback only (no interactive wizard needed)
  # Correct key is 'gateway.bind'; accepts: auto | loopback | lan | tailnet | custom
  run_cmd openclaw config set gateway.bind "loopback" || true

  log "Installing OpenClaw background daemon..."
  if ! run_cmd openclaw daemon install; then
    warn "Daemon install returned non-zero — may already be installed."
  fi

  log "Starting OpenClaw gateway..."
  if ! run_cmd openclaw gateway start; then
    warn "Gateway did not start cleanly — check: openclaw gateway status"
  fi

  success "OpenClaw gateway and daemon configured."
}

configure_openclaw_ollama() {
  section "Configuring OpenClaw ↔ Ollama integration"
  require_command openclaw "OpenClaw CLI"

  # OpenClaw 2026+ uses 'vllm' as the provider type for any OpenAI-compatible
  # backend (including Ollama). The onboarding wizard registers it as 'vllm',
  # so config paths must use that key — not 'ollama'.
  # Ollama's OpenAI-compatible API lives under /v1/ — the base URL must include it.
  oc_config_set models.providers.vllm.apiKey "ollama-local"
  oc_config_set models.providers.vllm.baseUrl "http://127.0.0.1:11434/v1"
  oc_config_set models.providers.vllm.api "openai-chat"
  oc_config_set agents.defaults.model.primary "vllm/${OLLAMA_META_MODEL_TAG}"

  success "Default model → vllm/${OLLAMA_META_MODEL_TAG}  (agent: ${GLADOS_AGENT_NAME})"
}

configure_openclaw_voice() {
  # Called from audio.sh after whisper/piper are set up.
  # Configures OpenClaw to use the local whisper-stt and piper-tts wrappers.
  require_command openclaw "OpenClaw CLI"

  # Note: OpenClaw has no voice config section — the glados-stt / glados-tts
  # wrappers invoke whisper.cpp and Piper directly, bypassing the gateway.
  success "Voice (STT/TTS) wrappers installed (standalone, not managed by OpenClaw)."
}

configure_openclaw_websearch() {
  # Called from internet.sh after SearXNG is running.
  require_command openclaw "OpenClaw CLI"
  local searxng_url="http://127.0.0.1:${SEARXNG_PORT}"

  # Built-in web_search tool (Brave API); enable so the agent can search.
  oc_config_set tools.web.search.enabled true
  oc_config_set tools.web.search.maxResults 5

  # Enable web_fetch so the agent can query SearXNG's JSON API directly:
  #   GET http://127.0.0.1:<port>/search?q=<query>&format=json
  oc_config_set tools.web.fetch.enabled true

  success "Web search enabled — SearXNG available at ${searxng_url}/search?format=json"
}

# Health helper
check_openclaw_health() {
  if command -v openclaw >/dev/null 2>&1; then
    local oc_ver
    oc_ver="$(openclaw --version 2>/dev/null || echo 'unknown')"
    echo -e "  ${GREEN}✔${NC}  OpenClaw CLI    : ${oc_ver}"
    if openclaw gateway status >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔${NC}  OpenClaw gateway: running"
    else
      echo -e "  ${YELLOW}⚠${NC}  OpenClaw gateway: not running (openclaw gateway start)"
    fi
    return 0
  else
    echo -e "  ${RED}✖${NC}  OpenClaw CLI    : not found"
    return 1
  fi
}
