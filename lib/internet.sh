#!/usr/bin/env bash
# =============================================================================
# lib/internet.sh — Internet / web-search integration via SearXNG
#
# Deploys a self-hosted SearXNG instance in Docker Compose and configures
# OpenClaw to use it as a web-search tool, giving the LLM access to
# real-time internet results.
#
# SearXNG is a privacy-respecting, aggregating meta-search engine that
# queries multiple public search APIs without sending user data to them.
#
# Service layout:
#   • SearXNG   http://127.0.0.1:<SEARXNG_PORT>
#   • Redis     (cache / rate-limit backend for SearXNG — internal only)
#
# Security:
#   • Both containers are bound to 127.0.0.1 only (not exposed externally)
#   • SECRET_KEY is randomly generated at install time
# =============================================================================

[[ -n "${_GLADOS_INTERNET_LOADED:-}" ]] && return 0
readonly _GLADOS_INTERNET_LOADED=1

install_internet_search() {
  section "Internet / web-search (SearXNG via Docker)"

  require_command docker "Docker"

  _generate_searxng_config
  _write_searxng_compose
  _start_searxng
  _wait_for_searxng

  configure_openclaw_websearch   # defined in openclaw.sh

  success "Web-search ready at http://127.0.0.1:${SEARXNG_PORT}"
}

# ---------------------------------------------------------------------------
# Generate SearXNG configuration files
# ---------------------------------------------------------------------------

_generate_searxng_config() {
  local cfg_dir="${SEARXNG_COMPOSE_DIR}/searxng"
  mkdir -p "$cfg_dir"

  # Generate a random secret key if not already present
  local secret_key_file="${cfg_dir}/.secret_key"
  if [[ ! -f "$secret_key_file" ]]; then
    local secret_key
    secret_key="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 48)"
    echo "$secret_key" >"$secret_key_file"
    chmod 600 "$secret_key_file"
    debug "Generated new SearXNG secret key."
  fi

  local secret_key
  secret_key="$(cat "${cfg_dir}/.secret_key")"

  # Write settings.yml only if it does not already exist (idempotent)
  if [[ -f "${cfg_dir}/settings.yml" ]]; then
    debug "SearXNG settings.yml already present — not overwriting."
    return
  fi

  cat >"${cfg_dir}/settings.yml" <<SEARXNG_SETTINGS
# SearXNG configuration — managed by GLaDOS Installer
# Edit this file to add/remove search engines or change behaviour.

general:
  debug: false
  instance_name: "GLaDOS Search"

server:
  # Bind only to localhost for security; Docker Compose exposes the port
  bind_address: "0.0.0.0"
  port: 8080
  secret_key: "${secret_key}"
  limiter: false        # no rate-limiting on local usage
  public_instance: false

search:
  safe_search: 0        # 0 = off, 1 = moderate, 2 = strict
  autocomplete: ""
  default_lang: "auto"
  formats:
    - html
    - json             # JSON endpoint used by OpenClaw tool integration

engines:
  # Core web engines
  - name: google
    engine: google
    categories: general
    disabled: false
  - name: bing
    engine: bing
    categories: general
    disabled: false
  - name: duckduckgo
    engine: duckduckgo
    categories: general
    disabled: false
  # News
  - name: google news
    engine: google_news
    categories: news
    disabled: false
  # Tech-specific
  - name: github
    engine: github
    categories: it
    disabled: false
  - name: stackoverflow
    engine: stackoverflow
    categories: it
    disabled: false
  # Science / academic
  - name: arxiv
    engine: arxiv
    categories: science
    disabled: false
  - name: semantic scholar
    engine: semantic_scholar
    categories: science
    disabled: false
  # Wikipedia (reliable factual base)
  - name: wikipedia
    engine: wikipedia
    categories: general
    language: auto
    disabled: false

ui:
  static_use_hash: true
  default_locale: ""
  query_in_title: false
  infinite_scroll: true
  center_alignment: false

outgoing:
  request_timeout: 5.0
  max_request_timeout: 10.0
  useragent_suffix: ""
SEARXNG_SETTINGS

  # Restrict permissions — settings.yml contains the secret_key
  chmod 600 "${cfg_dir}/settings.yml"

  success "SearXNG settings.yml written."
}

# ---------------------------------------------------------------------------
# Docker Compose file
# ---------------------------------------------------------------------------

_write_searxng_compose() {
  local compose_file="${SEARXNG_COMPOSE_DIR}/docker-compose.yml"

  if [[ -f "$compose_file" ]]; then
    debug "docker-compose.yml already present — not overwriting."
    return
  fi

  cat >"$compose_file" <<COMPOSE
# Docker Compose for SearXNG + Redis — managed by GLaDOS Installer
# Run: docker compose -f ${compose_file} up -d

services:
  redis:
    image: "valkey/valkey:8-alpine"
    container_name: glados-searxng-redis
    restart: unless-stopped
    command: valkey-server --save 30 1 --loglevel warning
    volumes:
      - searxng-redis-data:/data
    networks:
      - searxng-net

  searxng:
    image: "searxng/searxng:latest"
    container_name: glados-searxng
    restart: unless-stopped
    ports:
      # Bind to 127.0.0.1 only — not exposed on network
      - "127.0.0.1:${SEARXNG_PORT}:8080"
    environment:
      - SEARXNG_BASE_URL=http://127.0.0.1:${SEARXNG_PORT}/
      - UWSGI_THREADS=2         # keep it low for N4000
      - UWSGI_WORKERS=1
    volumes:
      - ./searxng:/etc/searxng:rw
    networks:
      - searxng-net
    depends_on:
      - redis
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  searxng-net:
    driver: bridge

volumes:
  searxng-redis-data:
COMPOSE

  success "SearXNG docker-compose.yml written."
}

# ---------------------------------------------------------------------------
# Start SearXNG
# ---------------------------------------------------------------------------

_start_searxng() {
  spinner_start "Starting SearXNG containers..."

  if [[ "$DRY_RUN" == true ]]; then
    spinner_stop
    info "[dry-run] Would run: docker compose -f ${SEARXNG_COMPOSE_DIR}/docker-compose.yml up -d"
    return
  fi

  local -a _compose
  read -ra _compose <<< "$(compose_cmd)"

  "${_compose[@]}" \
    -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" \
    --project-name glados-searxng \
    up -d --pull always 2>&1 | while IFS= read -r line; do
      debug "compose: ${line}"
    done

  spinner_stop
  success "SearXNG containers started."
}

# ---------------------------------------------------------------------------
# Wait for SearXNG to become healthy
# ---------------------------------------------------------------------------

_wait_for_searxng() {
  local timeout="$SEARXNG_HEALTH_TIMEOUT"
  local poll="$SEARXNG_HEALTH_POLL"
  local waited=0
  local url="http://127.0.0.1:${SEARXNG_PORT}/healthz"

  spinner_start "Waiting for SearXNG to be ready (max ${timeout}s)..."

  if [[ "$DRY_RUN" == true ]]; then
    spinner_stop
    info "[dry-run] Skipping SearXNG health wait."
    return
  fi

  while [[ $waited -lt $timeout ]]; do
    if curl -sfm 3 "$url" >/dev/null 2>&1; then
      spinner_stop
      success "SearXNG is healthy at http://127.0.0.1:${SEARXNG_PORT} ✔"
      return 0
    fi
    sleep "$poll"
    waited=$((waited + poll))
  done
  spinner_stop
  warn "SearXNG did not respond within ${timeout}s. Check: docker logs glados-searxng"
}

# ---------------------------------------------------------------------------
# Stop / teardown helpers (can be called manually if needed)
# ---------------------------------------------------------------------------

teardown_internet_search() {
  info "Stopping SearXNG containers..."
  local -a _compose
  read -ra _compose <<< "$(compose_cmd)"
  "${_compose[@]}" \
    -f "${SEARXNG_COMPOSE_DIR}/docker-compose.yml" \
    --project-name glados-searxng \
    down 2>/dev/null || true
  success "SearXNG stopped."
}

# ---------------------------------------------------------------------------
# Health helper
# ---------------------------------------------------------------------------

check_internet_health() {
  if curl -sfm 5 "http://127.0.0.1:${SEARXNG_PORT}/healthz" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC}  SearXNG         : http://127.0.0.1:${SEARXNG_PORT}"
    return 0
  else
    echo -e "  ${RED}✖${NC}  SearXNG         : unreachable (docker logs glados-searxng)"
    return 1
  fi
}
