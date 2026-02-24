#!/usr/bin/env bash
# =============================================================================
# lib/network.sh — Static IP configuration
#
# Optionally configures a static IP address on the primary network interface.
# This runs early in the installation process so that the server keeps a
# predictable address for all services deployed afterwards (SearXNG, Ollama,
# Telegram webhook, etc.).
#
# Supported backends (auto-detected):
#   1. NetworkManager (nmcli)
#   2. /etc/network/interfaces  (classic Debian ifupdown)
#
# The original configuration is backed up before any change.
# =============================================================================

[[ -n "${_GLADOS_NETWORK_LOADED:-}" ]] && return 0
readonly _GLADOS_NETWORK_LOADED=1

# Network-specific defaults (overridable via CLI flags)
STATIC_IP="${STATIC_IP:-}"
STATIC_GATEWAY="${STATIC_GATEWAY:-}"
STATIC_DNS="${STATIC_DNS:-1.1.1.1}"
STATIC_NETMASK="${STATIC_NETMASK:-24}"

###############################################################################
# Detect primary network interface
###############################################################################

_detect_primary_iface() {
  # Prefer the interface that currently holds the default route
  local iface
  iface="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -z "$iface" ]]; then
    # Fallback: first non-loopback interface that is UP
    iface="$(ip -o link show up 2>/dev/null \
      | awk -F': ' '!/lo/{print $2; exit}')"
  fi
  echo "$iface"
}

###############################################################################
# Detect current IP settings of an interface
###############################################################################

_current_ip_info() {
  local iface="$1"
  local ip_addr gateway dns

  ip_addr="$(ip -4 addr show "$iface" 2>/dev/null \
    | awk '/inet / {print $2; exit}')"
  gateway="$(ip -4 route show default dev "$iface" 2>/dev/null \
    | awk '{print $3; exit}')"
  dns="$(grep -m1 'nameserver' /etc/resolv.conf 2>/dev/null \
    | awk '{print $2}')"

  echo "${ip_addr:-?} ${gateway:-?} ${dns:-?}"
}

###############################################################################
# Interactive prompt — ask if user wants a static IP
###############################################################################

prompt_static_ip() {
  [[ "$SKIP_STATIC_IP" == true ]] && return 1

  local iface
  iface="$(_detect_primary_iface)"
  if [[ -z "$iface" ]]; then
    warn "Could not detect a primary network interface — skipping static IP."
    return 1
  fi

  local current
  current="$(_current_ip_info "$iface")"
  local cur_ip cur_gw cur_dns
  cur_ip="$(echo "$current" | awk '{print $1}')"
  cur_gw="$(echo "$current" | awk '{print $2}')"
  cur_dns="$(echo "$current" | awk '{print $3}')"

  echo
  echo -e "  ${BOLD}Current network (${iface})${NC}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo -e "  ${CYAN}IP address :${NC} ${cur_ip}"
  echo -e "  ${CYAN}Gateway    :${NC} ${cur_gw}"
  echo -e "  ${CYAN}DNS        :${NC} ${cur_dns}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo

  if ! confirm "Configure a static IP for this server?" "n"; then
    info "Keeping current (dynamic) network configuration."
    return 1
  fi

  # Suggest sensible defaults based on current values
  local default_ip="${cur_ip}"
  local default_gw="${cur_gw}"
  local default_dns="${cur_dns:-1.1.1.1}"

  prompt_value "Static IP (CIDR, e.g. 192.168.1.100/24)" "$default_ip" STATIC_IP
  prompt_value "Gateway" "$default_gw" STATIC_GATEWAY
  prompt_value "DNS server" "$default_dns" STATIC_DNS

  # Extract netmask from CIDR if present
  if [[ "$STATIC_IP" == *"/"* ]]; then
    STATIC_NETMASK="${STATIC_IP##*/}"
    STATIC_IP="${STATIC_IP%%/*}"
  fi

  echo
  echo -e "  ${BOLD}Proposed static configuration${NC}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo -e "  ${CYAN}Interface  :${NC} ${iface}"
  echo -e "  ${CYAN}IP address :${NC} ${STATIC_IP}/${STATIC_NETMASK}"
  echo -e "  ${CYAN}Gateway    :${NC} ${STATIC_GATEWAY}"
  echo -e "  ${CYAN}DNS        :${NC} ${STATIC_DNS}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo

  if ! confirm "Apply this static IP configuration?" "y"; then
    info "Static IP configuration cancelled."
    return 1
  fi

  return 0
}

###############################################################################
# Apply static IP — NetworkManager (nmcli)
###############################################################################

_apply_static_nmcli() {
  local iface="$1"

  info "Configuring static IP via NetworkManager (nmcli)..."

  local conn_name
  conn_name="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null \
    | grep ":${iface}$" | head -1 | cut -d: -f1)"

  if [[ -z "$conn_name" ]]; then
    conn_name="$iface"
    warn "No active connection found for ${iface} — using '${conn_name}' as connection name."
  fi

  run_cmd sudo nmcli con mod "$conn_name" \
    ipv4.addresses "${STATIC_IP}/${STATIC_NETMASK}" \
    ipv4.gateway   "${STATIC_GATEWAY}" \
    ipv4.dns       "${STATIC_DNS}" \
    ipv4.method    manual

  run_cmd sudo nmcli con up "$conn_name"
  success "Static IP applied via nmcli (conn: ${conn_name})."
}

###############################################################################
# Apply static IP — /etc/network/interfaces (ifupdown)
###############################################################################

_apply_static_ifupdown() {
  local iface="$1"
  local ifaces_file="/etc/network/interfaces"

  info "Configuring static IP via ${ifaces_file}..."

  # Backup original
  local backup
  backup="${ifaces_file}.bak.$(date '+%Y%m%d_%H%M%S')"
  run_cmd sudo cp "$ifaces_file" "$backup"
  success "Backup saved to ${backup}"

  # Convert CIDR prefix to dotted netmask for ifupdown compatibility
  local dotted_netmask
  dotted_netmask="$(_cidr_to_netmask "$STATIC_NETMASK")"

  # Build the static stanza
  local stanza
  stanza="$(cat <<EOF
# Static IP configured by GLaDOS Installer ($(date '+%Y-%m-%d %H:%M:%S'))
auto ${iface}
iface ${iface} inet static
    address ${STATIC_IP}
    netmask ${dotted_netmask}
    gateway ${STATIC_GATEWAY}
    dns-nameservers ${STATIC_DNS}
EOF
)"

  # Remove existing stanza for this interface, then append the new one.
  # Use awk instead of sed range-delete to avoid eating blank lines that
  # belong to adjacent stanzas.
  run_cmd sudo bash -c "
    awk -v iface='${iface}' '
      /^(auto|iface) / && \$0 ~ iface { skip=1; next }
      skip && /^[^ \t]/ { skip=0 }
      skip { next }
      { print }
    ' '${ifaces_file}' > '${ifaces_file}.tmp' && mv '${ifaces_file}.tmp' '${ifaces_file}'
    echo '' >> '${ifaces_file}'
    cat <<'STANZA' >> '${ifaces_file}'
${stanza}
STANZA
  "

  # Restart networking
  if systemctl is-active --quiet networking 2>/dev/null; then
    run_cmd sudo systemctl restart networking
  else
    run_cmd sudo ifdown "$iface" 2>/dev/null || true
    run_cmd sudo ifup "$iface"
  fi

  success "Static IP applied via ifupdown."
}

###############################################################################
# Apply static IP — netplan (Ubuntu / some Debian setups)
###############################################################################

_apply_static_netplan() {
  local iface="$1"
  local netplan_dir="/etc/netplan"
  local netplan_file="${netplan_dir}/99-glados-static.yaml"

  info "Configuring static IP via netplan..."

  run_cmd sudo mkdir -p "$netplan_dir"

  local content
  content="$(cat <<EOF
# Static IP configured by GLaDOS Installer ($(date '+%Y-%m-%d %H:%M:%S'))
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}/${STATIC_NETMASK}
      routes:
        - to: default
          via: ${STATIC_GATEWAY}
      nameservers:
        addresses:
          - ${STATIC_DNS}
EOF
)"

  run_cmd sudo bash -c "cat > '${netplan_file}' << 'NETPLAN'
${content}
NETPLAN
"

  run_cmd sudo netplan apply
  success "Static IP applied via netplan."
}

###############################################################################
# Main entry point — configure static IP
###############################################################################

configure_static_ip() {
  section "Static IP configuration"

  # Interactive prompt — returns 1 if user declines
  if ! prompt_static_ip; then
    return 0
  fi

  # Validate inputs
  _validate_ip "$STATIC_IP"      || fail "Invalid IP address: ${STATIC_IP}"
  _validate_ip "$STATIC_GATEWAY" || fail "Invalid gateway: ${STATIC_GATEWAY}"
  _validate_ip "$STATIC_DNS"     || fail "Invalid DNS: ${STATIC_DNS}"

  local iface
  iface="$(_detect_primary_iface)"
  [[ -z "$iface" ]] && fail "Cannot detect primary network interface."

  # Choose backend
  if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null; then
    _apply_static_nmcli "$iface"
  elif command -v netplan >/dev/null 2>&1; then
    _apply_static_netplan "$iface"
  elif [[ -f /etc/network/interfaces ]]; then
    _apply_static_ifupdown "$iface"
  else
    fail "No supported network backend found (nmcli, netplan, or ifupdown)."
  fi

  # Verify
  sleep 2
  local new_ip
  new_ip="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2; exit}')"
  if [[ "$new_ip" == "${STATIC_IP}/"* || "$new_ip" == "${STATIC_IP}" ]]; then
    success "Static IP verified: ${new_ip} on ${iface}"
  else
    warn "Expected ${STATIC_IP} but got ${new_ip}. Check configuration manually."
  fi
}

###############################################################################
# IP address validator (basic IPv4)
###############################################################################

_validate_ip() {
  local ip="$1"
  local IFS='.'
  # shellcheck disable=SC2206
  local -a octets=($ip)
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for o in "${octets[@]}"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    # Reject leading zeros (ambiguous octal representation)
    [[ "$o" =~ ^0[0-9]+$ ]] && return 1
    # Force base-10 interpretation
    (( 10#$o >= 0 && 10#$o <= 255 )) || return 1
  done
  return 0
}

###############################################################################
# CIDR prefix → dotted netmask conversion
###############################################################################

_cidr_to_netmask() {
  local cidr="$1"
  local mask_dec=$(( 0xFFFFFFFF << (32 - cidr) & 0xFFFFFFFF ))
  printf '%d.%d.%d.%d\n' \
    $(( (mask_dec >> 24) & 255 )) \
    $(( (mask_dec >> 16) & 255 )) \
    $(( (mask_dec >> 8)  & 255 )) \
    $(( mask_dec         & 255 ))
}

###############################################################################
# Health check — for --status
###############################################################################

check_network_static() {
  local iface
  iface="$(_detect_primary_iface)"
  if [[ -z "$iface" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  Network        : no interface detected"
    return 1
  fi

  local ip_addr
  ip_addr="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2; exit}')"
  local method="dynamic"

  # Check if interface is statically configured
  if command -v nmcli >/dev/null 2>&1; then
    local conn_name
    conn_name="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null \
      | grep ":${iface}$" | head -1 | cut -d: -f1)"
    if [[ -n "$conn_name" ]]; then
      local nm_method
      nm_method="$(nmcli -t -f ipv4.method con show "$conn_name" 2>/dev/null | cut -d: -f2)"
      [[ "$nm_method" == "manual" ]] && method="static"
    fi
  elif grep -q "iface ${iface} inet static" /etc/network/interfaces 2>/dev/null; then
    method="static"
  elif [[ -f /etc/netplan/99-glados-static.yaml ]]; then
    method="static"
  fi

  echo -e "  ${GREEN}✔${NC}  Network        : ${ip_addr} (${iface}, ${method})"
  return 0
}
