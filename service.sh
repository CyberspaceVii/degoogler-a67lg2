#!/system/bin/sh
WL=/data/adb/cyberspacevii/degoogler-a67lg2
[ -f "$WL/uninstall_updates" ] || exit 0
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 10
for pkg in $(cat "$WL/uninstall_updates"); do
  if pm path "$pkg" >/dev/null 2>&1; then
    echo "$pkg: $(pm uninstall "$pkg" 2>&1)"
  else
    echo "$pkg: already gone"
  fi
done > "$WL/firstboot.log" 2>&1
rm -f "$WL/uninstall_updates"
