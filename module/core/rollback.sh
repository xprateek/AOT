#!/system/bin/sh
# ============================================================
# AOT Rollback - Safe State Recovery [v1]
# ============================================================
# Cleans up stale iptables rules, routing policies, and
# interface state to ensure a 'Clean Slate' after exit or fail.
# ============================================================

. "$(dirname "$0")/backend-common.sh"
[ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

cleanup_all() {
    IFACE=$1
    log_info "Executing AOT Rollback for $IFACE"

    # Load config to know which DNS was in use
    [ -f "/data/adb/aot/aot.config" ] && . "/data/adb/aot/aot.config"
    DNS_TARGET=${CUSTOM_DNS1:-"8.8.8.8"}

    # 1. Stop Backends
    sh "$(dirname "$0")/backend-netd.sh" stop "$IFACE" >/dev/null 2>&1
    sh "$(dirname "$0")/backend-shell.sh" stop "$IFACE" >/dev/null 2>&1

    # 2. Force Clear Iptables NAT/FORWARD (Legacy cleanup)
    if [ -n "$AOT_UPSTREAM" ]; then
        iptables -t nat -D POSTROUTING -o "$AOT_UPSTREAM" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -o "$AOT_UPSTREAM" -j ACCEPT 2>/dev/null
    fi

    # 3. Clear DNS DNAT redirect rules
    iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null
    iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null

    # 4. Force Clear Policy Rules (priority 5000)
    ip rule del from all iif "$IFACE" priority 5000 2>/dev/null

    # 5. Interface Flush
    ip addr flush dev "$IFACE" 2>/dev/null
    ip link set "$IFACE" down 2>/dev/null

    log_info "Rollback Complete: System state is CLEAN for $IFACE."
}

case "$1" in
    "clean")
        cleanup_all "$2"
        ;;
esac
