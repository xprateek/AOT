#!/system/bin/sh
# ============================================================
# AOT Backend: Native (ndc/netd) [v1]
# ============================================================
# Primary AOSP-compliant backend using Android's native
# tethering stack for DHCP, DNS, and NAT routing.
# ============================================================

# Robust Sourcing of Common Helpers
CORE_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$CORE_DIR/backend-common.sh"
[ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

# Backend logic
setup_ndc() {
    IFACE=$1
    
    # 0. Check if interface exists
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        log_error "[ndc] Critical Failure: Interface $IFACE not found!"
        return 1
    fi

    # Load configuration if exists
    [ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
    
    # Ensure variables are NOT empty by falling back to exported defaults
    GW=${CUSTOM_GATEWAY:-$AOT_DEFAULT_GW}
    NM=${CUSTOM_NETMASK:-$AOT_DEFAULT_NM}
    CIDR=$(mask_to_cidr "$NM")
    DHCP_START=${CUSTOM_DHCP_START:-$AOT_DEFAULT_DHCP_START}
    DHCP_END=${CUSTOM_DHCP_END:-$AOT_DEFAULT_DHCP_END}

    # Final sanity check to prevent "IP / assigned" style errors
    [ -z "$GW" ] && GW="10.0.0.1"
    [ -z "$CIDR" ] || [ "$CIDR" = "0" ] && CIDR="24"
    [ -z "$DHCP_START" ] && DHCP_START="10.0.0.2"
    [ -z "$DHCP_END" ] && DHCP_END="10.0.0.254"

    # Double-Lock: Fail if critical variables are still malformed
    if [ "$GW" = "/" ] || [ -z "$GW" ] || [ "$CIDR" = "0" ]; then
        log_error "[ndd] Double-Lock FAILURE: Malformed networking config ($GW/$CIDR). Aborting setup."
        return 1
    fi

    log_info "[ndc] Setting up tether bridge on $IFACE ($GW/$CIDR)..."

    # 1. Kill Android's DHCP client on this iface
    #    ConnectivityService runs dhcpcd treating eth0 as an upstream internet
    #    connection. It fights and wins against our gateway IP assignment.
    pkill -f "dhcpcd.*$IFACE" 2>/dev/null
    pkill -f "dhclient.*$IFACE" 2>/dev/null
    
    # 2. Stop any existing tether state cleanly
    ndc tether interface remove "$IFACE" 2>/dev/null
    ndc nat disable "$IFACE" "$AOT_UPSTREAM" 0 2>/dev/null

    # 3. Assign gateway IP at the kernel level (Retrying to fight Android resets)
    ip addr flush dev "$IFACE" 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    
    RETRY_COUNT=0
    SUCCESS="false"
    while [ $RETRY_COUNT -lt 3 ]; do
        sleep 3 # Wait for interface to settle (increased for Redmi stability)
        if ip addr add "$GW/$CIDR" dev "$IFACE" 2>/dev/null; then
            log_info "[ndc] IP $GW/$CIDR assigned successfully to $IFACE"
            SUCCESS="true"
            break
        fi
        # Check if already assigned (perhaps by system or previous attempt)
        if get_iface_ip "$IFACE" | grep -q "$GW"; then
            log_info "[ndc] IP $GW already present on $IFACE"
            SUCCESS="true"
            break
        fi
        log_warn "[ndc] IP assignment failed for $IFACE (Attempt $((RETRY_COUNT + 1))/3). Retrying..."
        ip link set "$IFACE" up 2>/dev/null
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ "$SUCCESS" = "false" ]; then
        log_error "[ndc] Critical Failure: Failed to assign IP to $IFACE after 3 attempts."
    fi
    
    # Notify ndc about the change for internal state
    ip link set "$IFACE" up

    # 4. Start DHCP server with our range
    #    Only stop global tethering if this interface is the only one active
    OTHER_IFACE=""
    [ "$IFACE" = "eth0" ] && OTHER_IFACE="rndis0" || OTHER_IFACE="eth0"
    if ! ndc tether status 2>/dev/null | grep -q "$OTHER_IFACE"; then
        ndc tether stop 2>/dev/null
    fi
    ndc tether start "$DHCP_START" "$DHCP_END" 2>/dev/null
    ndc tether interface add "$IFACE" 2>/dev/null
    log_info "[ndc] DHCP server started: $DHCP_START - $DHCP_END on $IFACE"

    # 5. NAT Link
    if [ -n "$AOT_UPSTREAM" ]; then
        ndc nat enable "$IFACE" "$AOT_UPSTREAM" 0 2>/dev/null
        ndc ipfwd enable tethering 2>/dev/null
        echo 1 > /proc/sys/net/ipv4/ip_forward
        log_info "[ndc] NAT Linked: $IFACE → $AOT_UPSTREAM"
        
        # 6. AOT bypass rules
        apply_aot_policy "$IFACE" "$AOT_UPSTREAM"
        apply_aot_dns "$IFACE"
    fi
}

teardown_ndc() {
    IFACE=$1
    log_info "[ndc] Tearing down $IFACE"
    ndc tether interface remove "$IFACE" 2>/dev/null
    ndc nat disable "$IFACE" "$AOT_UPSTREAM" 0 2>/dev/null
    ndc tether stop 2>/dev/null
    ip addr flush dev "$IFACE" 2>/dev/null
    ip link set "$IFACE" down 2>/dev/null
}

# Entrypoint Handler
case "$1" in
    "start")
        setup_ndc "$2"
        ;;
    "stop")
        teardown_ndc "$2"
        ;;
esac
