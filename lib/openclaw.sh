#!/usr/bin/env bash
# =============================================================================
# lib/openclaw.sh — OpenClaw CLI: installation, onboarding and model config
# =============================================================================

[[ -n "${_GLADOS_OPENCLAW_LOADED:-}" ]] && return 0
readonly _GLADOS_OPENCLAW_LOADED=1

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
  section "OpenClaw onboarding wizard"
  require_command openclaw "OpenClaw CLI"

  echo
  echo -e "  ${BOLD}The onboarding wizard will:${NC}"
  echo -e "    • Configure authentication and security"
  echo -e "    • Set up the local gateway (ports, binding)"
  echo -e "    • Install the background daemon"
  echo -e "    • Optionally connect communication channels"
  echo
  echo -e "  ${BOLD}Recommended choices:${NC}"
  echo -e "    • Bind gateway to ${BOLD}127.0.0.1${NC} for security"
  echo -e "    • Accept daemon installation"
  echo
  echo -e "  ${DIM}Re-run any time: openclaw onboard --install-daemon${NC}"
  echo

  if [[ "$NON_INTERACTIVE" == true ]]; then
    warn "Non-interactive mode — onboard wizard requires interactive input."
  fi

  run_cmd openclaw onboard --install-daemon
  success "OpenClaw onboarding completed."
}

configure_openclaw_ollama() {
  section "Configuring OpenClaw ↔ Ollama integration"
  require_command openclaw "OpenClaw CLI"

  # Registers Ollama as a local provider (dummy key — Ollama is keyless)
  run_cmd openclaw config set models.providers.ollama.apiKey "ollama-local"
  run_cmd openclaw config set models.providers.ollama.baseUrl "http://127.0.0.1:11434"
  run_cmd openclaw config set agents.defaults.model.primary "ollama/${OLLAMA_META_MODEL_TAG}"
  run_cmd openclaw config set agents.defaults.label "${GLADOS_AGENT_NAME}" || true

  # Enable streaming for richer interactive feel
  run_cmd openclaw config set models.providers.ollama.streaming true || true

  success "Default model → ollama/${OLLAMA_META_MODEL_TAG}  (agent: ${GLADOS_AGENT_NAME})"
}

configure_openclaw_voice() {
  # Called from audio.sh after whisper/piper are set up.
  # Configures OpenClaw to use the local whisper-stt and piper-tts wrappers.
  require_command openclaw "OpenClaw CLI"

  run_cmd openclaw config set voice.stt.provider "whisper-local"
  run_cmd openclaw config set voice.stt.command "glados-stt"
  run_cmd openclaw config set voice.tts.provider "piper-local"
  run_cmd openclaw config set voice.tts.command "glados-tts"
  run_cmd openclaw config set voice.enabled true || true

  success "Voice (STT/TTS) configured in OpenClaw."
}

configure_openclaw_websearch() {
  # Called from internet.sh after SearXNG is running.
  require_command openclaw "OpenClaw CLI"
  local searxng_url="http://127.0.0.1:${SEARXNG_PORT}"

  run_cmd openclaw config set tools.webSearch.enabled true
  run_cmd openclaw config set tools.webSearch.provider "searxng"
  run_cmd openclaw config set tools.webSearch.baseUrl "${searxng_url}"
  run_cmd openclaw config set tools.webSearch.maxResults 5
  run_cmd openclaw config set agents.defaults.tools.webSearch true || true

  success "Web search (SearXNG → ${searxng_url}) configured in OpenClaw."
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
