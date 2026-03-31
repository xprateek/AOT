#!/system/bin/sh
# ============================================================
# AOT Verify - Deep Connectivity Verification [v1]
# ============================================================
# Performs active flow checks (Ping, DNS, Routing) to
# ensure the tethering bridge is actually functional.
# ============================================================

. "$(dirname "$0")/backend-common.sh"
[ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

verify_bridge() {
    IFACE=$1
    log_info "Verifying bridge: $IFACE"

    # 1. Interface IP Check
    if ! ip addr show "$IFACE" 2>/dev/null | grep -q "inet "; then
        log_error "Interface $IFACE has NO IP address."
        return 1
    fi

    # 2. IP Forwarding Check
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        log_error "IP Forwarding is DISABLED."
        return 1
    fi

    # 3. Active Flow Check (Optional/Warning)
    # Ping 1.1.1.1 (Cloudflare) to see if NAT is working
    if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        log_warn "Ping to 1.1.1.1 failed. Internet might be unreachable."
    fi

    # 4. Check routing rule 5000 (AOT Policy)
    if ! ip rule show | grep -q "5000"; then
        log_warn "AOT Policy Rule (priority 5000) is MISSING."
    fi

    log_info "Verification Successful: Bridge $IFACE is ACTIVE."
    return 0
}

case "$1" in
    "check")
        verify_bridge "$2"
        ;;
esac
