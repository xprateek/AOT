#!/system/bin/sh
# ============================================================
# AOT Diagnostics - Full System Intelligence [v1]
# ============================================================
# Generates a comprehensive snapshot of the device networking
# state for deep troubleshooting in the WebUI.
# ============================================================

. "$(dirname "$0")/backend-common.sh"
DIAG_FILE="/data/adb/aot/diag.txt"

log_info "Generating Deep Diagnostics Snapshot..."

{
    echo "=== AOT DIAGNOSTICS SNAPSHOT [$(date)] ==="
    echo "--- DEVICE ---"
    uname -a
    getprop ro.product.brand
    getprop ro.product.model
    getprop ro.build.version.sdk
    echo ""
    
    echo "--- KERNEL (RELEVANT) ---"
    dmesg | grep -Ei "usb|rndis|eth|rmnet" | tail -n 50
    echo ""

    echo "--- SYSTEM LOGS (WARNINGS) ---"
    logcat -d -t 50 *:W
    echo ""

    echo "--- INTERFACES ---"
    ip addr
    echo ""

    echo "--- ROUTING ---"
    ip route show
    echo ""
    echo "--- RULES ---"
    ip rule show
    echo ""

    echo "--- NETD / NDC ---"
    ndc tether status 2>/dev/null
    echo ""

    echo "--- FIREWALL (NAT) ---"
    iptables -t nat -S 2>/dev/null
    echo ""
    echo "--- FIREWALL (FORWARD) ---"
    iptables -S FORWARD 2>/dev/null
    echo ""

    echo "--- CONNECTIVITY ---"
    dumpsys connectivity | head -n 50
    echo ""

    echo "=== END SNAPSHOT ==="
} > "$DIAG_FILE"

log_info "Snapshot Complete: $DIAG_FILE"
