#!/system/bin/sh
# ============================================================
# AOT Backend: Shell (Fallback) [v1]
# ============================================================
# Manual networking backend using pure iptables/ip route
# for systems where ndc is restricted or unavailable.
# ============================================================

. "$(dirname "$0")/backend-common.sh"
[ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

# Backend logic
setup_shell() {
    IFACE=$1
    [ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
    IP_ADDRESS=${CUSTOM_GATEWAY:-"10.0.0.1"}
    NETMASK=${CUSTOM_NETMASK:-"255.255.255.0"}
    CIDR=$(mask_to_cidr "$NETMASK")
    
    log_info "[shell] Fallback Initializing $IFACE ($IP_ADDRESS/$CIDR)"

    # 1. Kill Android's DHCP client (same conflict as ndc backend)
    pkill -f "dhcpcd.*$IFACE" 2>/dev/null
    pkill -f "dhclient.*$IFACE" 2>/dev/null

    # 2. Assign IP at kernel level (survives netd interference)
    ip addr flush dev "$IFACE" 2>/dev/null
    ip addr add "$IP_ADDRESS/$CIDR" dev "$IFACE" 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    
    # 3. IP Forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # 4. Iptables NAT (MASQUERADE)
    if [ -n "$AOT_UPSTREAM" ]; then
        iptables -t nat -D POSTROUTING -o "$AOT_UPSTREAM" -j MASQUERADE 2>/dev/null
        iptables -t nat -A POSTROUTING -o "$AOT_UPSTREAM" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i "$IFACE" -o "$AOT_UPSTREAM" -j ACCEPT 2>/dev/null
        iptables -A FORWARD -i "$IFACE" -o "$AOT_UPSTREAM" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -i "$AOT_UPSTREAM" -o "$IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
        iptables -A FORWARD -i "$AOT_UPSTREAM" -o "$IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
        log_info "[shell] NAT Linked (MASQUERADE): $IFACE → $AOT_UPSTREAM"

        # 5. Critical Rules
        apply_aot_policy "$IFACE" "$AOT_UPSTREAM"
        apply_aot_dns "$IFACE"
    fi
}

teardown_shell() {
    IFACE=$1
    log_info "[shell] Tearing down $IFACE"
    if [ -n "$AOT_UPSTREAM" ]; then
        iptables -t nat -D POSTROUTING -o "$AOT_UPSTREAM" -j MASQUERADE 2>/dev/null
    fi
    ifconfig "$IFACE" 0.0.0.0 down 2>/dev/null
}

# Entrypoint Handler
case "$1" in
    "start")
        setup_shell "$2"
        ;;
    "stop")
        teardown_shell "$2"
        ;;
esac
