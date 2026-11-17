#!/system/bin/sh
[ "$(getprop ro.product.device)" = A67L_Gen2 ] || abort "Fail! This module is for the Foxxd A67L Gen 2."
[ "$KSU" = true ] || abort "Fail! KernelSU Next is required."
WL=/data/adb/cyberspacevii/degoogler-a67lg2
ACTIVE=/data/adb/modules/degoogler_a67lg2
. "$MODPATH/lib.sh"
. "$MODPATH/configure.sh"
