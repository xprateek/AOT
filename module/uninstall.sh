#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
PERSISTENT_DIR="/data/adb/aot"

echo "AOT: uninstalling and cleaning up..."

if [ -d "$PERSISTENT_DIR" ]; then
    rm -rf "$PERSISTENT_DIR"
fi

echo "AOT: cleanup completed."
