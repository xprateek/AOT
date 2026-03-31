#!/system/bin/sh
# ============================================================
# AOT Post-FS-Data Hook [v1]
# ============================================================
# Runs early at boot to prepare the persistent data directory.
# Network is NOT available at this stage — probe runs later
# in service.sh after boot_completed.
# ============================================================

MODDIR=${0%/*}

# Ensure base directories exist before service.sh runs
mkdir -p /data/adb/aot
chown -R root:root /data/adb/aot
chmod -R 755 /data/adb/aot

# Ensure all core scripts are executable
chmod 755 "$MODDIR"/core/*.sh 2>/dev/null
chmod 755 "$MODDIR"/aot-cli.sh 2>/dev/null

# Log the hook execution
echo "[$(date '+%H:%M:%S')] [POST-FS] Environment Ready" >> /data/adb/aot/aot.log
