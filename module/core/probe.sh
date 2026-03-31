#!/system/bin/sh
# ============================================================
# AOT Probe - Deep System Intelligence & Detection [v1]
# ============================================================
# Learns from AOSP/Codelinaro patterns to determine the best
# networking backend for modern Android systems (GKI 5.4+).
# ============================================================

. "$(dirname "$0")/backend-common.sh"

PROBE_ENV="/data/adb/aot/probe.env"
[ -f "$PROBE_ENV" ] && rm "$PROBE_ENV"

# Internal variables
SDK=$(getprop ro.build.version.sdk)
BRAND=$(getprop ro.product.brand)
MODEL=$(getprop ro.product.model)
KERNEL=$(uname -r)

log_info "Starting AOT Probe: $BRAND $MODEL (API $SDK, Kernel $KERNEL)"

# 1. Detect Firewall Backend
FIREWALL="iptables"
if has_cmd nft; then
    FIREWALL="nft"
fi

# 2. Detect NDC Support (AOSP Native Stack)
NDC_SUPPORT="false"
if has_cmd ndc; then
    # Test if tethering commands are recognized
    if ndc tether status >/dev/null 2>&1; then
        NDC_SUPPORT="true"
    fi
fi

# 3. Detect Interfaces
# Upstream (WAN)
UPSTREAM=""
UPSTREAM=$(ip route get 8.8.8.8 2>/dev/null | grep -o "dev [^ ]*" | cut -d' ' -f2 | head -n 1)
UPSTREAM_TYPE="Unknown"
if echo "$UPSTREAM" | grep -qE "rmnet|ccmni"; then
    UPSTREAM_TYPE="Cellular"
elif echo "$UPSTREAM" | grep -q "wlan"; then
    UPSTREAM_TYPE="WiFi"
elif [ -n "$UPSTREAM" ]; then
    UPSTREAM_TYPE="Other"
fi

if [ -z "$UPSTREAM" ]; then
    ip link show wlan0 2>/dev/null | grep -q "state UP" && UPSTREAM="wlan0" && UPSTREAM_TYPE="WiFi"
fi

# Local Interfaces (Tether candidates)
USB_IFACE=""
for iface in rndis0 usb0; do
    if ip link show "$iface" >/dev/null 2>&1; then
        USB_IFACE="$iface"
        break
    fi
done

ETH_IFACE=""
if ip link show eth0 >/dev/null 2>&1; then
    ETH_IFACE="eth0"
fi

# 4. Determine Recommended Backend
BACKEND="shell"
if [ "$NDC_SUPPORT" = "true" ]; then
    BACKEND="ndc"
fi

# 5. Output Environmental Variables
{
    echo "AOT_SDK=$SDK"
    echo "AOT_BRAND=$BRAND"
    echo "AOT_MODEL=$MODEL"
    echo "AOT_KERNEL=$KERNEL"
    echo "AOT_FIREWALL=$FIREWALL"
    echo "AOT_NDC_SUPPORT=$NDC_SUPPORT"
    echo "AOT_UPSTREAM=$UPSTREAM"
    echo "AOT_UPSTREAM_TYPE=$UPSTREAM_TYPE"
    echo "AOT_USB_IFACE=$USB_IFACE"
    echo "AOT_ETH_IFACE=$ETH_IFACE"
    echo "AOT_RECOMMENDED_BACKEND=$BACKEND"
} > "$PROBE_ENV"

log_info "Probe Complete: Recommended Backend is [$BACKEND]"
log_info "Environmental data written to $PROBE_ENV"
