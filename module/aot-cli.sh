#!/system/bin/sh
# ============================================================
# AOT (Always On Tethering) - Modular Orchestrator [v1.0.0]
# ============================================================
# High-resilience networking engine that orchestrates
# modular backends (ndc vs shell) for universal Android compatibility.
# ============================================================

# Robust Path Resolution
MODDIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$MODDIR/core"
. "$CORE_DIR/backend-common.sh"

ACTION=$1
STATE=$2
PROBE_ENV="/data/adb/aot/probe.env"

# Ensure probe data exists before proceeding
if [ ! -f "$PROBE_ENV" ] && [ "$ACTION" != "probe" ]; then
    sh "$CORE_DIR/probe.sh"
fi
[ -f "$PROBE_ENV" ] && . "$PROBE_ENV"

# ============================================================
# Task Orchestration
# ============================================================
start_tethering() {
    IFACE=$1
    log_info "[v1] Starting Tethering Engine on $IFACE..."

    # Selection logic: Prefer ndc if supported
    if [ "$AOT_NDC_SUPPORT" = "true" ]; then
        sh "$CORE_DIR/backend-netd.sh" start "$IFACE"
    else
        sh "$CORE_DIR/backend-shell.sh" start "$IFACE"
    fi

    # Verify the work
    sleep 2
    if sh "$CORE_DIR/verify.sh" check "$IFACE"; then
        log_info "[v1] SUCCESS: Tethering bridge is ACTIVE."
    else
        log_warn "[v1] WARNING: Verification failed. Attempting fallback..."
    fi
}

stop_tethering() {
    IFACE=$1
    sh "$CORE_DIR/rollback.sh" clean "$IFACE"
}

# ============================================================
# CLI Command Handler
# ============================================================
case "$ACTION" in
    "usb")
        if [ "$STATE" = "enable" ]; then
            log_info "[AOT] Initializing USB Tethering..."
            settings put global tether_supported 1
            
            # Smart USB Config: Check if already enabled or need transition
            CUR_CONFIG=$(getprop sys.usb.config)
            CUR_STATE=$(getprop sys.usb.state)
            
            # ADB check
            HAS_ADB="false"
            case "$CUR_CONFIG" in *adb*) HAS_ADB="true" ;; esac
            
            # Check if RNDIS is already active to avoid dropping ADB
            case "$CUR_STATE" in
                *rndis*) 
                    log_info "[AOT] USB RNDIS is already active. Skipping reset."
                    ;;
                *)
                    log_info "[AOT] Transitioning USB to RNDIS (ADB=$HAS_ADB)..."
                    if has_cmd "svc"; then
                        svc usb setFunctions rndis "$HAS_ADB"
                    else
                        [ "$HAS_ADB" = "true" ] && NEW_CONF="rndis,adb" || NEW_CONF="rndis"
                        setprop sys.usb.config "$NEW_CONF"
                    fi
                    
                    # Settle period for Android Gadget (API 31+)
                    log_info "[AOT] Waiting 5s for USB gadget to settle..."
                    sleep 5
                    ;;
            esac
            
            # Create persistent flag
            touch "$PERSISTENT_DIR/usb_enabled"
            
            # Wait for rndis0 to appear (max 15s)
            MAX_RETRY=15
            while [ $MAX_RETRY -gt 0 ]; do
                if ip link show rndis0 >/dev/null 2>&1; then 
                    ip link set rndis0 up
                    break 
                fi
                sleep 1
                MAX_RETRY=$((MAX_RETRY - 1))
            done
            
            # Detect upstream and start backend
            sh "$CORE_DIR/probe.sh"
            [ -f "$PROBE_ENV" ] && . "$PROBE_ENV"
            start_tethering "rndis0"
        elif [ "$STATE" = "disable" ]; then
            log_info "[AOT] Disabling USB Tethering..."
            stop_tethering "rndis0"
            
            # Restore to standard ADB or None
            CUR_CONFIG=$(getprop sys.usb.config)
            HAS_ADB="false"
            case "$CUR_CONFIG" in *adb*) HAS_ADB="true" ;; esac
            
            if has_cmd "svc"; then
                svc usb setFunctions none "$HAS_ADB"
            else
                [ "$HAS_ADB" = "true" ] && setprop sys.usb.config "adb" || setprop sys.usb.config "none"
            fi
            
            # Remove persistent flags
            rm -f "$PERSISTENT_DIR/usb_enabled"
        fi
        ;;
    "adb-tcp")
        if [ "$STATE" = "enable" ]; then
            AOT_PORT=${3:-"5555"}
            CUR_PORT=$(getprop service.adb.tcp.port)
            if [ "$CUR_PORT" = "$AOT_PORT" ]; then
                log_info "[AOT] ADB over TCP is already active on port $AOT_PORT. Skipping reset."
            else
                log_info "[AOT] Enabling ADB over TCP on port $AOT_PORT..."
                setprop service.adb.tcp.port "$AOT_PORT"
                stop adbd
                sleep 2
                start adbd
                
                # Critical: If USB tethering was active, check if it needs repair
                if [ -f "$PERSISTENT_DIR/usb_enabled" ]; then
                    log_warn "[AOT] Re-verifying USB bridge after ADB restart..."
                    if ! ip addr show rndis0 2>/dev/null | grep -q "inet "; then
                        log_info "[AOT] Repairing rndis0 IP after ADB reset..."
                        [ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
                        GW=${CUSTOM_GATEWAY:-"10.0.0.1"}
                        NM=${CUSTOM_NETMASK:-"255.255.255.0"}
                        CIDR=$(mask_to_cidr "$NM")
                        ip addr add "$GW/$CIDR" dev rndis0 2>/dev/null
                        ip link set rndis0 up 2>/dev/null
                    fi
                fi
            fi
            touch "$PERSISTENT_DIR/wifiadb_enabled"
            # Maintain a clean config
            sed -i "/WIFI_ADB_PORT=/d" "$PERSISTENT_DIR/aot.config" 2>/dev/null
            echo "WIFI_ADB_PORT=\"$AOT_PORT\"" >> "$PERSISTENT_DIR/aot.config"
        elif [ "$STATE" = "disable" ]; then
            log_info "[AOT] Disabling ADB over TCP (USB-only mode)..."
            setprop service.adb.tcp.port "-1"
            stop adbd
            sleep 2
            start adbd
            rm -f "$PERSISTENT_DIR/wifiadb_enabled"
        fi
        ;;
    "eth")
        if [ "$STATE" = "enable" ]; then
            log_info "[AOT] Initializing Ethernet Tethering..."
            settings put global tether_supported 1
            
            # Dynamic Discovery
            ETH_IFACE=$(find_ethernet_iface)
            if [ -z "$ETH_IFACE" ]; then
                log_error "[AOT] No Ethernet adapter detected. Please plug in your OTG adapter."
                exit 1
            fi

            # Create persistent flag
            touch "$PERSISTENT_DIR/eth_enabled"
            
            # Bring interface up
            log_info "[AOT] Bringing up interface $ETH_IFACE..."
            ip link set "$ETH_IFACE" up 2>/dev/null
            
            # Settle period for Ethernet Adapter
            log_info "[AOT] Waiting 5s for Ethernet adapter to stabilize..."
            sleep 5
            
            # Detect upstream before starting
            sh "$CORE_DIR/probe.sh"
            [ -f "$PROBE_ENV" ] && . "$PROBE_ENV"
            start_tethering "$ETH_IFACE"
        elif [ "$STATE" = "disable" ]; then
            ETH_IFACE=$(find_ethernet_iface)
            [ -z "$ETH_IFACE" ] && ETH_IFACE="eth0" # Fallback for teardown
            log_info "[AOT] Disabling Ethernet Tethering on $ETH_IFACE..."
            stop_tethering "$ETH_IFACE"
            rm -f "$PERSISTENT_DIR/eth_enabled"
        fi
        ;;
    "test")
        sh "$CORE_DIR/automated_tests.sh"
        ;;
    "probe")
        sh "$CORE_DIR/probe.sh"
        ;;
    "verify")
        sh "$CORE_DIR/verify.sh" check "$STATE"
        ;;
    "diag")
        sh "$CORE_DIR/diag.sh"
        ;;
    "clear_logs")
        echo "[AOT] Log cleared." > "$LOG_FILE"
        ;;
    "ping")
        IP=${2:-"1.1.1.1"}
        IFACE=""
        [ -f "$PERSISTENT_DIR/usb_enabled" ] && IFACE="rndis0"
        if [ -f "$PERSISTENT_DIR/eth_enabled" ] && [ -z "$IFACE" ]; then
            IFACE=$(find_ethernet_iface)
            [ -z "$IFACE" ] && IFACE="eth0"
        fi
        
        if [ -n "$IFACE" ]; then
            echo "[AOT] Pinging $IP via $IFACE..."
            ping -c 4 -I "$IFACE" "$IP"
        else
            echo "[!] No active AOT interface to ping through."
        fi
        ;;
    "status")
        JSON_OUTPUT="{"
        IS_JSON="false"
        [ "$2" = "--json" ] && IS_JSON="true"
        
        # Load Defaults for reference
        . "$CORE_DIR/backend-common.sh"
        [ -f "$PERSISTENT_DIR/aot.config" ] && . "$PERSISTENT_DIR/aot.config"
        GW=${CUSTOM_GATEWAY:-$AOT_DEFAULT_GW}
        
        if [ -f "$PERSISTENT_DIR/usb_enabled" ]; then
            IP=$(get_iface_ip "rndis0")
            [ "$IS_JSON" = "false" ] && echo "USB (Active) - Gateway: $GW - Client IP: ${IP:-N/A}"
            JSON_OUTPUT="${JSON_OUTPUT}\"usb\":{\"active\":true,\"gateway\":\"$GW\",\"ip\":\"${IP:-N/A}\"},"
        else
            JSON_OUTPUT="${JSON_OUTPUT}\"usb\":{\"active\":false},"
        fi
        
        if [ -f "$PERSISTENT_DIR/eth_enabled" ]; then
            ETH_IFACE=$(find_ethernet_iface)
            [ -z "$ETH_IFACE" ] && ETH_IFACE="eth0"
            IP=$(get_iface_ip "$ETH_IFACE")
            [ "$IS_JSON" = "false" ] && echo "Ethernet (Active) - Interface: $ETH_IFACE - Gateway: $GW - IP: ${IP:-N/A}"
            JSON_OUTPUT="${JSON_OUTPUT}\"eth\":{\"active\":true,\"iface\":\"$ETH_IFACE\",\"gateway\":\"$GW\",\"ip\":\"${IP:-N/A}\"},"
        else
            JSON_OUTPUT="${JSON_OUTPUT}\"eth\":{\"active\":false},"
        fi
        
        # Add basic system info
        UPSTREAM=$(ip route get 8.8.8.8 2>/dev/null | grep -o "dev [^ ]*" | cut -d' ' -f2 | head -n 1)
        JSON_OUTPUT="${JSON_OUTPUT}\"upstream\":\"${UPSTREAM:-none}\","
        JSON_OUTPUT="${JSON_OUTPUT}\"version\":\"v1.0.0\"}"
        
        if [ "$IS_JSON" = "true" ]; then
            echo "$JSON_OUTPUT"
        elif [ ! -f "$PERSISTENT_DIR/usb_enabled" ] && [ ! -f "$PERSISTENT_DIR/eth_enabled" ]; then
            echo "AOT Status: Idle (v1.0.0)"
        fi
        ;;
    *)
        print_banner
        echo "AOT v1.0.0 Modular CLI"
        echo "Usage: $0 <usb|eth|adb-tcp|probe|verify|diag|test|ping|clear_logs|status> [enable|disable|iface] [port/ip]"
        ;;
esac
