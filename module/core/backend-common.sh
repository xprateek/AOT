#!/system/bin/sh
# ============================================================
# AOT Backend Common - Shared Helpers & Professional Logging [v1]
# ============================================================

LOG_FILE="/data/adb/aot/aot.log"
PERSISTENT_DIR="/data/adb/aot"
[ ! -d "$PERSISTENT_DIR" ] && mkdir -p "$PERSISTENT_DIR"

# AOT Default Networking (v1.0.0)
export AOT_DEFAULT_GW="10.0.0.1"
export AOT_DEFAULT_NM="255.255.255.0"
export AOT_DEFAULT_DHCP_START="10.0.0.2"
export AOT_DEFAULT_DHCP_END="10.0.0.254"
export AOT_DEFAULT_DNS="8.8.8.8"

# Standard AOT Logging
log_info() {
    echo "[$(date '+%H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
    echo "$1"
}

print_banner() {
    cat << "EOF"
  O   o-o  o-O-o 
 / \ o   o   |   
o---o|   |   |   
|   |o   o   |   
o   o o-o    o   

  Always-On Tethering (AOT) v1.0.0
  High-Performance Networking Bridge
  - Source: github.com/xprateek
  - AOT by xprateek
EOF
}

log_warn() {
    echo "[$(date '+%H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
    echo "WARNING: $1"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] [ERR!] $1" >> "$LOG_FILE"
    echo "ERROR: $1"
}

# Command existence check
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# CIDR conversion helper
mask_to_cidr() {
    MASK=${1:-"255.255.255.0"}
    [ "$MASK" = "24" ] && echo "24" && return
    IFS=.
    set -- $MASK
    BITS=0
    for octet; do
        # Ensure octet is a number
        clean_octet=$(echo "$octet" | tr -dc '0-9')
        [ -z "$clean_octet" ] && clean_octet=0
        while [ "$clean_octet" -ne 0 ]; do
            BITS=$((BITS + (clean_octet % 2)))
            clean_octet=$((clean_octet / 2))
        done
    done
    echo "${BITS:-24}"
}

# Dynamic Interface Discovery
find_ethernet_iface() {
    # Scan for ethX, usbX, or enpX (common for Ethernet-to-USB adapters)
    # Exclude loopback, rndis0, wlan0, rmnet, etc.
    IFACES=$(ip link show | grep -E "^[0-9]+: (eth|usb|enp|enw|eth_usb)[0-9]+" | cut -d":" -f2 | cut -d" " -f2 | grep -vE "rndis0|wlan0|p2p0|rmnet|dummy|lo|ifb|sit0")
    if [ -n "$IFACES" ]; then
        # Pick the first one that is UP, otherwise the first one found
        # (This is better than head -n 1 as it prioritizes active links)
        UP_IFACE=""
        for iface in $IFACES; do
            if ip link show "$iface" | grep -q "state UP"; then
                UP_IFACE="$iface"
                break
            fi
        done
        echo "${UP_IFACE:-$(echo "$IFACES" | head -n 1)}"
    else
        echo ""
    fi
}

# Helper to get IP for an interface
get_iface_ip() {
    ip addr show "$1" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1
}

# Safe command runner with timeout
run_with_timeout() {
    TIMEOUT=$1
    shift
    # Simple shell-based timeout simulation
    "$@" &
    PID=$!
    ( sleep "$TIMEOUT" && kill -HUP "$PID" >/dev/null 2>&1 ) &
    WATCHDOG=$!
    wait "$PID"
    ret=$?
    kill "$WATCHDOG" >/dev/null 2>&1
    return $ret
}

# Apply AOT Routing Policy (Priority 5000)
apply_aot_policy() {
    IFACE=$1
    UPSTREAM=$2
    [ -z "$UPSTREAM" ] && return
    
    # Aggressive Injection: Ensure no duplicates then force apply
    ip rule del from all iif "$IFACE" lookup "$UPSTREAM" priority 5000 2>/dev/null
    
    # Check if rule already exists via alternate check before adding
    if ip rule show | grep -q "from all iif $IFACE lookup $UPSTREAM priority 5000"; then
        log_info "Policy bypass ALREADY ACTIVE: $IFACE → lookup $UPSTREAM"
        return 0
    fi

    if ip rule add from all iif "$IFACE" lookup "$UPSTREAM" priority 5000; then
        log_info "Policy bypass SUCCESS: $IFACE → lookup $UPSTREAM (priority 5000)"
    else
        # Success if it failed but rule is present
        if ip rule show | grep -q "from all iif $IFACE lookup $UPSTREAM priority 5000"; then
             log_info "Policy bypass ACTIVE (pre-existing): $IFACE → lookup $UPSTREAM"
        else
            log_error "Policy bypass FAILED for $IFACE. Verify SELinux/Root."
        fi
    fi
}

# Apply DNS DNAT Redirection
apply_aot_dns() {
    IFACE=$1
    [ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
    DNS_TARGET=${CUSTOM_DNS1:-"8.8.8.8"}
    
    # Flush existing rules for this iface first (prevents duplication on repair cycles)
    iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null
    iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null

    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 53 -j DNAT --to-destination "$DNS_TARGET" 2>/dev/null
    log_info "DNS redirect: $IFACE → $DNS_TARGET"
}

# Check if system NAT is already active
is_nat_active() {
    IFACE=$1
    # Check for Magisk/KernelSU tetherctrl or standard NAT rules
    iptables -t nat -S | grep -E "tetherctrl_nat_POSTROUTING|MASQUERADE|POSTROUTING" | grep -q "$IFACE"
}

# Check for active cellular connection
is_cellular_active() {
    # Check if default route is via rmnet (typical for cellular)
    ip route get 8.8.8.8 2>/dev/null | grep -qE "rmnet|ccmni" && return 0
    # Fallback to system properties
    [ "$(getprop gsm.network.type)" != "Unknown" ] && [ -n "$(getprop gsm.network.type)" ] && return 0
    return 1
}

# Wait for interface to obtain an IP address
wait_for_interface_stability() {
    IFACE=$1
    MAX_WAIT=${2:-30}
    log_info "Waiting for interface $IFACE to stabilize (max ${MAX_WAIT}s)..."
    while [ $MAX_WAIT -gt 0 ]; do
        if get_iface_ip "$IFACE" | grep -q "\."; then
            log_info "Interface $IFACE is STABLE with IP: $(get_iface_ip "$IFACE")"
            return 0
        fi
        sleep 1
        MAX_WAIT=$((MAX_WAIT - 1))
    done
    log_warn "Interface $IFACE failed to stabilize within timeout."
    return 1
}
