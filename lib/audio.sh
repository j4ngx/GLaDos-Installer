#!/usr/bin/env bash
# =============================================================================
# lib/audio.sh — Voice input/output for GLaDOS
#
# Installs and configures:
#   • whisper.cpp     — offline speech-to-text  (STT) via ggml models
#   • Piper TTS       — offline text-to-speech  (TTS)
#   • glados-stt      — wrapper: record mic → transcribe → print text
#   • glados-tts      — wrapper: pipe text → synthesise → play audio
#   • glados-voice    — interactive voice chat loop with the LLM
#
# Hardware notes (Intel N4000 / 8 GB RAM):
#   • whisper model "small" (~460 MB) gives the best speed/accuracy balance
#   • Use "tiny" for faster inference on very constrained hardware
#   • Piper is CPU-only and extremely lightweight (~100 ms/sentence)
# =============================================================================

[[ -n "${_GLADOS_AUDIO_LOADED:-}" ]] && return 0
readonly _GLADOS_AUDIO_LOADED=1

# ---------------------------------------------------------------------------
# Internal paths (relative to WHISPER_INSTALL_DIR / PIPER_INSTALL_DIR)
# ---------------------------------------------------------------------------

_whisper_binary() { echo "${WHISPER_INSTALL_DIR}/build/bin/whisper-cli"; }
_whisper_model()  { echo "${WHISPER_INSTALL_DIR}/models/ggml-${WHISPER_MODEL}.bin"; }

# ---------------------------------------------------------------------------
# Main entry point (called by glados_installer.sh)
# ---------------------------------------------------------------------------

install_audio() {
  section "Voice interface (Whisper STT + Piper TTS)"

  select_piper_voice
  _install_whisper_cpp
  _download_whisper_model
  _install_piper_tts
  _install_glados_stt_wrapper
  _install_glados_tts_wrapper
  _install_glados_voice_chat

  configure_openclaw_voice   # defined in openclaw.sh

  success "Voice interface ready — run ${BOLD}glados-voice${NC} to start."
}

# ---------------------------------------------------------------------------
# whisper.cpp — build from source for best performance on x86_64
# ---------------------------------------------------------------------------

_install_whisper_cpp() {
  local binary
  binary="$(_whisper_binary)"

  if [[ -x "$binary" ]]; then
    success "whisper.cpp already built at ${binary}."
    return
  fi

  mkdir -p "$WHISPER_INSTALL_DIR"

  # Clone or update
  if [[ -d "${WHISPER_INSTALL_DIR}/.git" ]]; then
    spinner_start "Updating whisper.cpp source..."
    run_cmd git -C "$WHISPER_INSTALL_DIR" pull --ff-only
    spinner_stop
  else
    spinner_start "Cloning whisper.cpp..."
    run_cmd git clone --depth 1 \
      https://github.com/ggerganov/whisper.cpp.git \
      "$WHISPER_INSTALL_DIR"
    spinner_stop
  fi

  # Build — OPENBLAS acceleration when available
  spinner_start "Compiling whisper.cpp (may take 3-5 min on N4000)..."
  local cmake_flags=(-DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON)
  if dpkg -l libopenblas-dev >/dev/null 2>&1; then
    cmake_flags+=(-DGGML_OPENBLAS=ON)
    debug "OpenBLAS acceleration enabled."
  fi

  # Build inside the whisper.cpp directory; pass cmake flags as positional args
  # to avoid word-splitting issues with array expansion in bash -c strings.
  run_cmd bash -c '
    cd "$1" || exit 1
    shift
    cmake -B build "$@" -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -j"$(nproc)"
  ' _ "${WHISPER_INSTALL_DIR}" "${cmake_flags[@]}"
  spinner_stop

  [[ -x "$binary" ]] || fail "whisper.cpp build failed — binary not found at ${binary}."
  success "whisper.cpp compiled ✔"

  # Clean build artifacts to reclaim ~500 MB of disk
  _clean_whisper_build_artifacts
}

# ---------------------------------------------------------------------------
# Download the GGML Whisper model
# ---------------------------------------------------------------------------

_download_whisper_model() {
  local model_file
  model_file="$(_whisper_model)"

  if [[ -f "$model_file" ]]; then
    success "Whisper model '${WHISPER_MODEL}' already present."
    return
  fi

  mkdir -p "$(dirname "$model_file")"
  local url="${WHISPER_MODELS_URL}/ggml-${WHISPER_MODEL}.bin"

  spinner_start "Downloading Whisper '${WHISPER_MODEL}' model..."
  retry "Whisper model download" \
    curl -fL --connect-timeout 30 --max-time 1800 \
      "$url" -o "$model_file"
  spinner_stop

  [[ -s "$model_file" ]] || fail "Whisper model download produced an empty file."

  local size_mb
  size_mb="$(du -m "$model_file" | cut -f1)"
  success "Whisper model '${WHISPER_MODEL}' downloaded (${size_mb} MB) ✔"
}

# ---------------------------------------------------------------------------
# Piper TTS — pre-built binary for amd64 / arm64
# ---------------------------------------------------------------------------

_install_piper_tts() {
  if [[ -x "${PIPER_BIN_DIR}/piper" ]]; then
    success "Piper TTS already installed."
    _download_piper_voice
    return
  fi

  mkdir -p "$PIPER_INSTALL_DIR" "$PIPER_BIN_DIR"

  # Determine platform tarball
  local arch
  arch="$(uname -m)"
  local tarball_name
  case "$arch" in
    x86_64)         tarball_name="piper_linux_x86_64.tar.gz" ;;
    aarch64|arm64)  tarball_name="piper_linux_aarch64.tar.gz" ;;
    *)
      warn "No pre-built Piper binary for ${arch}. TTS will be unavailable."
      return
      ;;
  esac

  local url="${PIPER_RELEASES_URL}/${tarball_name}"
  local tmptar
  tmptar="$(mktemp "${TMPDIR:-/tmp}/piper_XXXXXXXXXX.tar.gz")"

  spinner_start "Downloading Piper TTS..."
  retry "Piper TTS download" \
    curl -fL --connect-timeout 30 --max-time 300 "$url" -o "$tmptar"
  spinner_stop

  spinner_start "Extracting Piper TTS..."
  run_cmd tar -xzf "$tmptar" -C "$PIPER_INSTALL_DIR" --strip-components=1
  rm -f "$tmptar"
  spinner_stop

  # Symlink piper binary into PATH
  if [[ -x "${PIPER_INSTALL_DIR}/piper" ]]; then
    run_cmd ln -sf "${PIPER_INSTALL_DIR}/piper" "${PIPER_BIN_DIR}/piper"
    success "Piper TTS installed ✔"
  else
    warn "Piper binary not found after extraction at ${PIPER_INSTALL_DIR}/piper."
    return
  fi

  _download_piper_voice
}

_download_piper_voice() {
  _download_piper_voice_by_catalog
}

# ---------------------------------------------------------------------------
# glados-stt  — record microphone → WAV → whisper → stdout text
# ---------------------------------------------------------------------------

_install_glados_stt_wrapper() {
  local script="${PIPER_BIN_DIR}/glados-stt"
  local whisper_bin
  whisper_bin="$(_whisper_binary)"
  local model_file
  model_file="$(_whisper_model)"

  cat >"$script" <<GLADOS_STT
#!/usr/bin/env bash
# glados-stt: record ${GLADOS_AGENT_NAME}'s microphone input and transcribe it.
# Usage:  glados-stt [seconds_to_record]   default: 5
# Output: plain-text transcription on stdout.

set -euo pipefail

SECONDS_RECORD="\${1:-5}"
WHISPER_BIN="${whisper_bin}"
MODEL="${model_file}"
TMP_WAV="\$(mktemp /tmp/glados_rec_XXXXXXXXXX.wav)"

cleanup() { rm -f "\$TMP_WAV"; }
trap cleanup EXIT

# Record via ALSA (arecord) or fallback to sox
if command -v arecord >/dev/null 2>&1; then
  arecord -q -f S16_LE -r 16000 -c 1 -d "\$SECONDS_RECORD" "\$TMP_WAV" 2>/dev/null
elif command -v sox >/dev/null 2>&1; then
  rec -q -r 16000 -c 1 -b 16 "\$TMP_WAV" trim 0 "\$SECONDS_RECORD" 2>/dev/null
else
  echo "ERROR: no audio capture tool found (install alsa-utils or sox)" >&2
  exit 1
fi

# Whisper: output only the transcription text (no timestamps, no progress)
"\$WHISPER_BIN" \\
  -m "\$MODEL"  \\
  -f "\$TMP_WAV" \\
  -l auto       \\
  --no-timestamps \\
  --output-txt /dev/stdout \\
  2>/dev/null   \\
  | grep -v "^\$"
GLADOS_STT

  chmod +x "$script"
  success "glados-stt installed at ${script}"
}

# ---------------------------------------------------------------------------
# glados-tts  — read text from stdin → synthesise speech → play
# ---------------------------------------------------------------------------

_install_glados_tts_wrapper() {
  local script="${PIPER_BIN_DIR}/glados-tts"
  local piper_bin="${PIPER_BIN_DIR}/piper"
  local onnx="${PIPER_INSTALL_DIR}/voices/${PIPER_DEFAULT_VOICE}.onnx"
  local json="${PIPER_INSTALL_DIR}/voices/${PIPER_DEFAULT_VOICE}.onnx.json"

  cat >"$script" <<GLADOS_TTS
#!/usr/bin/env bash
# glados-tts: read text from stdin and speak it using Piper TTS.
# Usage:  echo "Hello" | glados-tts
#         glados-tts <<< "Hello world"

set -euo pipefail

PIPER_BIN="${piper_bin}"
ONNX="${onnx}"
JSON="${json}"
TMP_WAV="\$(mktemp /tmp/glados_tts_XXXXXXXXXX.wav)"

cleanup() { rm -f "\$TMP_WAV"; }
trap cleanup EXIT

# Synthesise
"\$PIPER_BIN" \\
  --model "\$ONNX"        \\
  --config "\$JSON"       \\
  --output_file "\$TMP_WAV" \\
  2>/dev/null

# Play — prefer aplay (ALSA), fallback to sox play
if command -v aplay >/dev/null 2>&1; then
  aplay -q "\$TMP_WAV" 2>/dev/null
elif command -v play >/dev/null 2>&1; then
  play -q "\$TMP_WAV" 2>/dev/null
else
  echo "WARNING: no audio playback tool found (install alsa-utils or sox)" >&2
fi
GLADOS_TTS

  chmod +x "$script"
  success "glados-tts installed at ${script}"
}

# ---------------------------------------------------------------------------
# glados-voice  — interactive voice chat loop
# ---------------------------------------------------------------------------

_install_glados_voice_chat() {
  local script="${PIPER_BIN_DIR}/glados-voice"

  cat >"$script" <<'GLADOS_VOICE'
#!/usr/bin/env bash
# ==========================================================================
# glados-voice — Interactive voice chat with the local LLM via OpenClaw
#
# Usage:
#   glados-voice [--model llama3] [--no-tts] [--record-secs 6]
#
# Controls (during a session):
#   Enter    : start a new recording
#   q        : quit
# ==========================================================================

set -Eeuo pipefail

MODEL="${GLADOS_VOICE_MODEL:-}"
USE_TTS=true
RECORD_SECS=6

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)      shift; MODEL="$1" ;;
    --no-tts)     USE_TTS=false ;;
    --record-secs) shift; RECORD_SECS="$1" ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--model TAG] [--no-tts] [--record-secs N]"
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# Resolve model: prefer explicit arg, then openclaw config, then default
if [[ -z "$MODEL" ]] && command -v openclaw >/dev/null 2>&1; then
  MODEL="$(openclaw config get agents.defaults.model.primary 2>/dev/null | sed 's|^ollama/||' || echo '')"
fi
MODEL="${MODEL:-llama3}"

command -v glados-stt >/dev/null 2>&1 || { echo "ERROR: glados-stt not found. Run the GLaDOS installer." >&2; exit 1; }
command -v openclaw   >/dev/null 2>&1 || { echo "ERROR: openclaw not found." >&2; exit 1; }

echo
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  GLaDOS Voice Chat  │  model: ${MODEL}              │"
echo "  │  Press ENTER to speak  ·  Type q + ENTER to quit    │"
echo "  └─────────────────────────────────────────────────────┘"
echo

while true; do
  printf "\n  [ENTER to record / q to quit] "
  read -r cmd
  [[ "${cmd,,}" == "q" ]] && { echo "Goodbye."; break; }

  echo "  🎙  Listening for ${RECORD_SECS}s..."
  TRANSCRIPT="$(glados-stt "$RECORD_SECS" 2>/dev/null)"
  TRANSCRIPT="$(echo "$TRANSCRIPT" | xargs)"   # trim whitespace

  if [[ -z "$TRANSCRIPT" ]]; then
    echo "  (nothing detected — try again)"
    continue
  fi

  echo "  You: ${TRANSCRIPT}"
  echo

  # Send to LLM via OpenClaw CLI
  RESPONSE="$(openclaw ask --model "$MODEL" --no-stream "$TRANSCRIPT" 2>/dev/null)"

  echo "  GLaDOS: ${RESPONSE}"

  if [[ "$USE_TTS" == true ]] && command -v glados-tts >/dev/null 2>&1; then
    echo "$RESPONSE" | glados-tts
  fi
done
GLADOS_VOICE

  chmod +x "$script"
  success "glados-voice installed at ${script} — run it to start a voice session."

  # Helpful alias hint
  echo
  echo -e "  ${DIM}Add to your shell profile: alias glados='glados-voice'${NC}"
}

# ---------------------------------------------------------------------------
# Build artifact cleanup (~500 MB savings)
# ---------------------------------------------------------------------------

_clean_whisper_build_artifacts() {
  local build_dir="${WHISPER_INSTALL_DIR}/build"
  [[ -d "$build_dir" ]] || return 0

  # Keep only the final binaries; remove CMake intermediaries, .o files, etc.
  local before_kb after_kb saved_mb
  before_kb="$(du -sk "$build_dir" 2>/dev/null | cut -f1)"

  # Remove object files, CMake temp dirs, and static libs
  find "$build_dir" -type f \( -name '*.o' -o -name '*.a' -o -name '*.cmake' \) -delete 2>/dev/null || true
  find "$build_dir" -type d -name 'CMakeFiles' -exec rm -rf {} + 2>/dev/null || true
  rm -rf "${build_dir}/_deps" 2>/dev/null || true
  rm -rf "${build_dir}/CMakeCache.txt" 2>/dev/null || true
  rm -rf "${build_dir}/Makefile" 2>/dev/null || true

  after_kb="$(du -sk "$build_dir" 2>/dev/null | cut -f1)"
  saved_mb="$(( (before_kb - after_kb) / 1024 ))"

  if [[ $saved_mb -gt 0 ]]; then
    success "Cleaned whisper.cpp build artifacts — ${saved_mb} MB reclaimed."
  fi
}

# ---------------------------------------------------------------------------
# Interactive Piper voice selection
# ---------------------------------------------------------------------------

# A curated list of popular Piper voices for en_US / en_GB.
# Format: "short_name|hf_path|onnx_file|description"
readonly _PIPER_VOICE_CATALOG=(
  "en_US-amy-medium|en/en_US/amy/medium|en_US-amy-medium|Amy (US, medium, default)"
  "en_US-amy-low|en/en_US/amy/low|en_US-amy-low|Amy (US, low quality, faster)"
  "en_US-lessac-medium|en/en_US/lessac/medium|en_US-lessac-medium|Lessac (US, medium)"
  "en_US-lessac-high|en/en_US/lessac/high|en_US-lessac-high|Lessac (US, high quality)"
  "en_US-ryan-medium|en/en_US/ryan/medium|en_US-ryan-medium|Ryan (US, male, medium)"
  "en_US-kusal-medium|en/en_US/kusal/medium|en_US-kusal-medium|Kusal (US, male, medium)"
  "en_GB-cori-medium|en/en_GB/cori/medium|en_GB-cori-medium|Cori (GB, female, medium)"
  "en_GB-alan-medium|en/en_GB/alan/medium|en_GB-alan-medium|Alan (GB, male, medium)"
)

select_piper_voice() {
  # If PIPER_VOICE was set via CLI, use it directly
  if [[ -n "${PIPER_VOICE:-}" ]]; then
    PIPER_DEFAULT_VOICE="$PIPER_VOICE"
    info "Using CLI-specified Piper voice: ${PIPER_DEFAULT_VOICE}"
    return
  fi

  [[ "$NON_INTERACTIVE" == true ]] && return

  echo
  echo -e "  ${BOLD}Available Piper TTS voices:${NC}"
  local i=0
  for entry in "${_PIPER_VOICE_CATALOG[@]}"; do
    i=$((i + 1))
    local desc="${entry##*|}"
    local name="${entry%%|*}"
    local marker=""
    [[ "$name" == "$PIPER_DEFAULT_VOICE" ]] && marker=" ${GREEN}← current${NC}"
    echo -e "    ${BOLD}${i}.${NC} ${desc}${marker}"
  done
  echo

  local _voice_choice=""
  prompt_value "Select voice number (1-${#_PIPER_VOICE_CATALOG[@]})" "1" _voice_choice

  if [[ "$_voice_choice" =~ ^[0-9]+$ ]] && \
     [[ "$_voice_choice" -ge 1 ]] && \
     [[ "$_voice_choice" -le "${#_PIPER_VOICE_CATALOG[@]}" ]]; then
    local chosen="${_PIPER_VOICE_CATALOG[$((_voice_choice - 1))]}"
    PIPER_DEFAULT_VOICE="${chosen%%|*}"
    success "Voice set to: ${PIPER_DEFAULT_VOICE}"
  else
    warn "Invalid choice — keeping default voice: ${PIPER_DEFAULT_VOICE}"
  fi
}

_download_piper_voice_by_catalog() {
  # Called by _download_piper_voice; resolves voice paths from catalog
  local target_name="$PIPER_DEFAULT_VOICE"
  for entry in "${_PIPER_VOICE_CATALOG[@]}"; do
    local name="${entry%%|*}"
    if [[ "$name" == "$target_name" ]]; then
      local rest="${entry#*|}"
      local hf_path="${rest%%|*}"
      rest="${rest#*|}"
      local onnx_name="${rest%%|*}"

      local voice_dir="${PIPER_INSTALL_DIR}/voices"
      local onnx="${voice_dir}/${onnx_name}.onnx"
      local json="${voice_dir}/${onnx_name}.onnx.json"

      if [[ -f "$onnx" && -f "$json" ]]; then
        success "Piper voice '${target_name}' already present."
        return
      fi

      mkdir -p "$voice_dir"
      local base_url="https://huggingface.co/rhasspy/piper-voices/resolve/main"

      spinner_start "Downloading Piper voice '${target_name}'..."
      retry "Piper voice onnx" \
        curl -fL --connect-timeout 30 --max-time 300 \
          "${base_url}/${hf_path}/${onnx_name}.onnx" -o "$onnx"
      retry "Piper voice config" \
        curl -fL --connect-timeout 30 --max-time 60 \
          "${base_url}/${hf_path}/${onnx_name}.onnx.json" -o "$json"
      spinner_stop

      [[ -s "$onnx" ]] || fail "Piper voice model download failed."
      success "Piper voice '${target_name}' downloaded ✔"
      return
    fi
  done

  # Fallback: voice not in catalog — try the old hardcoded path logic
  warn "Voice '${target_name}' not in catalog — attempting generic download."
  _download_piper_voice_legacy
}

_download_piper_voice_legacy() {
  local voice_dir="${PIPER_INSTALL_DIR}/voices"
  local onnx="${voice_dir}/${PIPER_DEFAULT_VOICE}.onnx"
  local json="${voice_dir}/${PIPER_DEFAULT_VOICE}.onnx.json"

  if [[ -f "$onnx" && -f "$json" ]]; then
    success "Piper voice '${PIPER_DEFAULT_VOICE}' already present."
    return
  fi

  mkdir -p "$voice_dir"
  local base_url="https://huggingface.co/rhasspy/piper-voices/resolve/main"
  local hf_path="en/en_US/amy/medium"

  spinner_start "Downloading Piper voice model '${PIPER_DEFAULT_VOICE}'..."
  retry "Piper voice onnx" \
    curl -fL --connect-timeout 30 --max-time 300 \
      "${base_url}/${hf_path}/${PIPER_DEFAULT_VOICE}.onnx" -o "$onnx"
  retry "Piper voice config" \
    curl -fL --connect-timeout 30 --max-time 60 \
      "${base_url}/${hf_path}/${PIPER_DEFAULT_VOICE}.onnx.json" -o "$json"
  spinner_stop

  [[ -s "$onnx" ]] || fail "Piper voice model download failed."
  success "Piper voice '${PIPER_DEFAULT_VOICE}' downloaded ✔"
}

# ---------------------------------------------------------------------------
# Health helper
# ---------------------------------------------------------------------------

check_audio_health() {
  local ok=true

  if [[ -x "$(_whisper_binary)" ]]; then
    echo -e "  ${GREEN}✔${NC}  whisper.cpp     : $(_whisper_binary)"
  else
    echo -e "  ${RED}✖${NC}  whisper.cpp     : not built"
    ok=false
  fi

  if [[ -f "$(_whisper_model)" ]]; then
    echo -e "  ${GREEN}✔${NC}  Whisper model   : ${WHISPER_MODEL}"
  else
    echo -e "  ${RED}✖${NC}  Whisper model   : ${WHISPER_MODEL} (missing)"
    ok=false
  fi

  if [[ -x "${PIPER_BIN_DIR}/piper" ]]; then
    echo -e "  ${GREEN}✔${NC}  Piper TTS       : installed"
  else
    echo -e "  ${YELLOW}⚠${NC}  Piper TTS       : not installed"
  fi

  if [[ -x "${PIPER_BIN_DIR}/glados-voice" ]]; then
    echo -e "  ${GREEN}✔${NC}  glados-voice    : ${PIPER_BIN_DIR}/glados-voice"
  fi

  [[ "$ok" == true ]]
}
