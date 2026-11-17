#!/system/bin/sh
WL=/data/adb/cyberspacevii/degoogler-a67lg2
# APK/data backups are deliberately retained; never restore over replacements.
rm -f "$WL/choice" "$WL/uninstall_updates" "$WL/firstboot.log" \
  "$WL/stop_linkturbo" "$WL/facelock_off" "$WL/cleanup.log" \
  "$WL/cleanup-pending" "$WL/cleanup-pending.next"
rmdir "$WL/backups" "$WL" /data/adb/cyberspacevii 2>/dev/null
