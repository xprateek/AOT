#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODDIR="/data/adb/modules/aot-tethering"
PERSISTENT_DIR="/data/adb/aot"

magisk_webui_redirect=1

# read webui setting here
[ -f $PERSISTENT_DIR/webui_setting.sh ] && . $PERSISTENT_DIR/webui_setting.sh

# detect magisk environment here
# no need to redirect if inside mmrl
if [ -z "$MMRL" ] && [ ! -z "$MAGISKTMP" ] && [ $magisk_webui_redirect = 1 ] ; then
	pm path io.github.a13e300.ksuwebui > /dev/null 2>&1 && {
		echo "- Launching WebUI in KSUWebUIStandalone..."
		am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "aot-tethering"
		exit 0
	}
	pm path com.dergoogler.mmrl.wx > /dev/null 2>&1 && {
		echo "- Launching WebUI in WebUI X..."
		am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" -e MOD_ID "aot-tethering"
		exit 0
	}
fi

echo "AOT Tethering action executed."
exit 0
