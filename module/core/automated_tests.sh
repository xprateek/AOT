#!/system/bin/sh
# ============================================================
# AOT Automated Test Suite with Auto-Repair [v1.1]
# ============================================================

FIX_MODE="false"
[ "$1" = "--fix" ] && FIX_MODE="true"

CORE_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$CORE_DIR/backend-common.sh"
[ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

echo "------------------------------------------------------------"
echo "  AOT Health Check & Logic Validation"
echo "------------------------------------------------------------"

# 1. Environment Check
echo -n "[ ] SELinux Status: "
getenforce
echo -n "[ ] Root Access: "
[ "$(id -u)" -eq 0 ] && echo "PASS (root)" || echo "FAIL (non-root)"

# 2. Upstream Check
CUR_UPS=$(ip route get 8.8.8.8 2>/dev/null | grep -o "dev [^ ]*" | cut -d' ' -f2 | head -n 1)
echo "[ ] Upstream WAN: $CUR_UPS"

# 3. Policy Rule Check (Priority 5000)
echo -n "[ ] Logic Integrity (Priority 5000): "
if ip rule show | grep -q "5000"; then
    echo "PASS"
    ip rule show | grep "5000" | while read -r line; do
        echo "    -> $line"
    done
else
    echo "FAIL"
    if [ "$FIX_MODE" = "true" ]; then
        echo "    -> Attempting Auto-Repair..."
        [ -f "$PERSISTENT_DIR/usb_enabled" ] && sh "$(dirname "$0")/../aot-cli.sh" usb enable >/dev/null
        [ -f "$PERSISTENT_DIR/eth_enabled" ] && sh "$(dirname "$0")/../aot-cli.sh" eth enable >/dev/null
    fi
fi

# 4. NAT Table Check
echo -n "[ ] NAT Rules (MASQUERADE): "
if iptables -t nat -S | grep -q "MASQUERADE"; then
    echo "PASS"
else
    echo "FAIL"
    if [ "$FIX_MODE" = "true" ]; then
        echo "    -> Attempting Auto-Repair..."
        sh "$(dirname "$0")/../aot-cli.sh" probe >/dev/null
        # Trigger re-enable if session exists
        [ -f "$PERSISTENT_DIR/usb_enabled" ] && sh "$(dirname "$0")/../aot-cli.sh" usb enable >/dev/null
        [ -f "$PERSISTENT_DIR/eth_enabled" ] && sh "$(dirname "$0")/../aot-cli.sh" eth enable >/dev/null
    fi
fi

# 5. DNS Redirection Check
echo "[ ] DNS Redirection (Port 53):"
iptables -t nat -S | grep "DNAT" | grep "53" | while read -r line; do
    echo "    -> $line"
done

# 6. Service Watchdog Check
echo -n "[ ] Service Watchdog: "
pgrep -f "\-\-watchdog" >/dev/null && echo "RUNNING" || echo "NOT RUNNING"

# 7. Battery Safety Check
BAT_CAP=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "N/A")
echo "[ ] Battery Level: $BAT_CAP%"

# 8. Configuration Setup
[ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
echo "[ ] DHCP Logic: ${USE_CUSTOM_DHCP:-native (default)}"

# 9. Connectivity Validation
echo "------------------------------------------------------------"
echo "  Flow Validation (Gateway -> Upstream)"
echo "------------------------------------------------------------"
IFACE=""
[ -f "$PERSISTENT_DIR/usb_enabled" ] && IFACE="rndis0"
if [ -f "$PERSISTENT_DIR/eth_enabled" ] && [ -z "$IFACE" ]; then
    IFACE=$(find_ethernet_iface)
    [ -z "$IFACE" ] && IFACE="eth0"
fi

if [ -n "$IFACE" ]; then
    echo -n "[ ] Ping 1.1.1.1 via $IFACE: "
    if ping -c 1 -W 2 -I "$IFACE" 1.1.1.1 >/dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL (Routing/NAT bottleneck)"
    fi

    echo -n "[ ] DNS Resolution (google.com): "
    if nslookup google.com >/dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL (DNS Redirection bottleneck)"
    fi
else
    echo "[!] Skipping flow checks: No active AOT interface detected."
fi

echo "------------------------------------------------------------"
echo "  Diagnostic Summary Complete"
echo "------------------------------------------------------------"
