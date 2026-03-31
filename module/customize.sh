#!/bin/sh
PERSISTENT_DIR=/data/adb/aot
[ ! -d "$PERSISTENT_DIR" ] && mkdir -p "$PERSISTENT_DIR"

ui_print ""
ui_print "  O   o-o  o-O-o "
ui_print " / \ o   o   |   "
ui_print "o---o|   |   |   "
ui_print "|   |o   o   |   "
ui_print "o   o o-o    o   "
ui_print ""
ui_print "- Source: github.com/xprateek"
ui_print "- AOT by xprateek"
ui_print ""
ui_print "- Extracting module files..."

# Set default state on first installation
[ ! -d "$PERSISTENT_DIR" ] && mkdir -p "$PERSISTENT_DIR"

# Set permissions for AOT-CLI
busybox chmod +x "$MODPATH/aot-cli.sh"
