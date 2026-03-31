#!/system/bin/sh
# ============================================================
# AOT Watchdog Service - State-Aware Resilience [v1]
# ============================================================
# Instead of blindly restarting, this watchdog verifies the
# active bridge state and performs 'Smart Repairs' only when
# a connectivity failure is detected.
# ============================================================

MODDIR=${0%/*}
CORE_DIR="$MODDIR/core"
. "$CORE_DIR/backend-common.sh"

wait_for_boot() {
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 5
    done
    # Extra grace period for networking stack and cellular to initialize
    # User requested 120s for Redmi stability
    log_info "[v1-Service] Waiting 120s for system stability..."
    sleep 120
}

# Principal Loop
watchdog_loop() {
    # 0. Cellular Connection Verification
    log_info "[v1-Service] Verifying Cellular Connection..."
    MAX_CELL_WAIT=15
    while [ $MAX_CELL_WAIT -gt 0 ]; do
        if is_cellular_active; then
            log_info "[v1-Service] Cellular connection verified."
            break
        fi
        sleep 2
        MAX_CELL_WAIT=$((MAX_CELL_WAIT - 1))
    done
    [ $MAX_CELL_WAIT -le 0 ] && log_warn "[v1-Service] Continuing without confirmed cellular connection."

    # Run initial probe now that network is available
    sh "$CORE_DIR/probe.sh"
    [ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"

    # --- Initial State Restoration (Always-On) ---
    [ -f "$PERSISTENT_DIR/usb_enabled" ] && log_info "[v1-Service] Always-On: Restoring USB..." && sh "$MODDIR/aot-cli.sh" usb enable
    [ -f "$PERSISTENT_DIR/eth_enabled" ] && log_info "[v1-Service] Always-On: Restoring Ethernet..." && sh "$MODDIR/aot-cli.sh" eth enable
    # ---------------------------------------------

    while true; do
        # 0. Battery Safety Check (Threshold 5%)
        [ -f "/sys/class/power_supply/battery/capacity" ] && BAT_CAP=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null) || BAT_CAP="100"
        if [ "$BAT_CAP" -lt 5 ]; then
            log_error "[v1-Service] CRITICAL: Battery Low (${BAT_CAP}%). Stopping services to protect hardware."
            sh "$MODDIR/aot-cli.sh" usb disable
            sh "$MODDIR/aot-cli.sh" eth disable
            sleep 60
            continue
        fi

        # 1. Check Desired State
        USB_WANTED="false"
        [ -f "/data/adb/aot/usb_enabled" ] && USB_WANTED="true"

        ETH_WANTED="false"
        [ -f "/data/adb/aot/eth_enabled" ] && ETH_WANTED="true"

        # 2. Handoff Detection
        HANDOFF_TRIGGERED="false"

        # 3. Dynamic Optimization: Re-probe if upstream changed
        CUR_UPSTREAM=$(ip route get 8.8.8.8 2>/dev/null | grep -o "dev [^ ]*" | cut -d' ' -f2 | head -n 1)
        [ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"
        
        if [ -n "$CUR_UPSTREAM" ] && [ "$CUR_UPSTREAM" != "$AOT_UPSTREAM" ]; then
            log_info "[v1-Service] Network handoff detected ($AOT_UPSTREAM → $CUR_UPSTREAM). Re-probing..."
            sh "$CORE_DIR/probe.sh"
            [ -f "/data/adb/aot/probe.env" ] && . "/data/adb/aot/probe.env"
            
            # Re-apply NAT rules for active interfaces
            if [ "$USB_WANTED" = "true" ]; then
                log_info "[v1-Service] Repairing NAT for rndis0 after handoff..."
                sh "$MODDIR/aot-cli.sh" usb enable
            fi
            if [ "$ETH_WANTED" = "true" ]; then
                log_info "[v1-Service] Repairing NAT for Ethernet after handoff..."
                sh "$MODDIR/aot-cli.sh" eth enable
            fi

            HANDOFF_TRIGGERED="true"
        fi

        # Only run verify-based repairs if no handoff just triggered a re-enable
        if [ "$HANDOFF_TRIGGERED" = "false" ]; then
            REPAIR_DONE="false"
            if [ "$USB_WANTED" = "true" ]; then
                if ! sh "$CORE_DIR/verify.sh" check "rndis0" >/dev/null 2>&1; then
                    log_warn "[v1-Service] USB Tethering failure detected. Attempting repair..."
                    sh "$MODDIR/aot-cli.sh" usb enable
                    REPAIR_DONE="true"
                fi
            fi

            # Hotplug & Auto-Enable for Ethernet
            if [ "$ETH_WANTED" = "true" ] && [ "$REPAIR_DONE" = "false" ]; then
                HOT_IFACE=$(find_ethernet_iface)
                if [ -n "$HOT_IFACE" ]; then
                    if ! sh "$CORE_DIR/verify.sh" check "$HOT_IFACE" >/dev/null 2>&1; then
                        log_info "[v1-Service] HOTPLUG: Adapter $HOT_IFACE detected or bridge down. Repairing..."
                        sh "$MODDIR/aot-cli.sh" eth enable
                        REPAIR_DONE="true"
                    fi
                fi
            fi
            
            if [ "$REPAIR_DONE" = "true" ]; then
                sleep 20
                continue
            fi
        fi

        # 4. ADB over Tethering Watchdog
        if [ -f "/data/adb/aot/wifiadb_enabled" ]; then
            # Verify interface stability before starting/restoring ADB
            IFACE_READY="false"
            if [ "$USB_WANTED" = "true" ]; then
                get_iface_ip "rndis0" | grep -q "\." && IFACE_READY="true"
            fi
            if [ "$ETH_WANTED" = "true" ] && [ "$IFACE_READY" = "false" ]; then
                HOT_IFACE=$(find_ethernet_iface)
                [ -n "$HOT_IFACE" ] && get_iface_ip "$HOT_IFACE" | grep -q "\." && IFACE_READY="true"
            fi

            if [ "$IFACE_READY" = "true" ]; then
                AOT_ADB_PORT="5555"
                [ -f "/data/adb/aot/aot.config" ] && . "/data/adb/aot/aot.config"
                [ -n "$WIFI_ADB_PORT" ] && AOT_ADB_PORT="$WIFI_ADB_PORT"

                CUR_PORT=$(getprop service.adb.tcp.port)
                if [ "$CUR_PORT" != "$AOT_ADB_PORT" ]; then
                    log_info "[v1-Service] Interface stable. Starting ADB over Tethering on port $AOT_ADB_PORT..."
                    setprop service.adb.tcp.port "$AOT_ADB_PORT"
                    stop adbd
                    start adbd
                fi
            else
                log_warn "[v1-Service] ADB requested but no stable tethering interface found. Waiting..."
            fi
        fi

        sleep 10
    done
}

# Internal Watchdog Handler
if [ "$1" = "--watchdog" ]; then
    wait_for_boot
    # AOT Persistence: Protect from OOM Killer
    echo -1000 > /proc/self/oom_score_adj 2>/dev/null
    log_info "[v1-Service] AOT Watchdog Started (UPTIME: $(uptime)). persistent=true"
    watchdog_loop
    exit 0
fi

# Start Service
print_banner >> "$LOG_FILE"
log_info "[v1-Service] Initializing persistent background watchdog..."
nohup sh "$0" --watchdog > /dev/null 2>&1 &
