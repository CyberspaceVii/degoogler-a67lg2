#!/system/bin/sh
[ "$(getprop ro.product.device)" = A67L_Gen2 ] || abort "Fail! This module is for the Foxxd A67L Gen 2."
[ "$KSU" = true ] || abort "Fail! KernelSU Next is required."


TIMEOUT=30
WL=/data/adb/cyberspacevii/degoogler-a67lg2
mkdir -p "$WL"
rm -f "$WL/choice" "$WL/uninstall_updates"

getkey() {
  f="$MODPATH/.kev"; ans="none"; n=0; max=$(( $1 * 10 ))
  : > "$f"
  getevent -lq > "$f" 2>/dev/null &
  gp=$!
  while [ "$n" -lt "$max" ]; do
    if grep -qE 'KEY_VOLUMEUP +DOWN' "$f" 2>/dev/null; then ans="up"; break; fi
    if grep -qE 'KEY_VOLUMEDOWN +DOWN' "$f" 2>/dev/null; then ans="down"; break; fi
    sleep 0.1; n=$(( n + 1 ))
  done
  kill "$gp" 2>/dev/null
  rm -f "$f"
  echo "$ans"
}

whiteout() {
  rc=0
  for p in "$@"; do
    mkdir -p "$MODPATH/$(dirname "$p")" || rc=1
    mknod "$MODPATH/$p" c 0 0 2>/dev/null && chmod 644 "$MODPATH/$p" || rc=1
  done
  return $rc
}

say_result() { if [ "$1" = 0 ]; then ui_print "Success!"; else ui_print "Fail!"; fi; }

TRIM="system/product/app/GoogleLocationHistory
system/product/app/com.google.mainline.go.telemetry
system/system_ext/priv-app/GoogleFeedback"

FULL="system/product/priv-app/GmsCoreGo
system/system_ext/priv-app/GoogleServicesFramework
system/product/priv-app/Phonesky
system/product/priv-app/GooglePartnerSetup
system/product/priv-app/Turbo
system/product/priv-app/ConfigUpdater
system/product/priv-app/GoogleOneTimeInitializer
system/product/priv-app/GoogleRestore
system/product/priv-app/AssistantGo
system/product/priv-app/GoogleSearchGo"

UPDATED="com.google.android.gms com.android.vending com.google.android.partnersetup com.google.android.apps.restore com.google.android.apps.searchlite"

NAMES="A. Keep Google, trim telemetry (Morphe root mount)
B. Full microG - remove Google Play services
C. Keep Google, trim telemetry (Morphe + MicroG-RE)
Cancel - install nothing"

ui_print "Degoogler CyberspaceVII"
ui_print " "
ui_print "Volume Down = next choice, Volume Up = select"
ui_print "(Cancel after ${TIMEOUT}s). Read the README first!"
ui_print " "

i=1; pick=""
while [ -z "$pick" ]; do
  ui_print "> $(echo "$NAMES" | sed -n "${i}p")"
  case "$(getkey "$TIMEOUT")" in
    up)   pick=$i ;;
    down) i=$(( i % 4 + 1 )) ;;
    *)    pick=4 ;;
  esac
done
ui_print " "

case "$pick" in
  1) choice=A ;;
  2) choice=B ;;
  3) choice=C ;;
  *) abort "Cancelled - nothing installed" ;;
esac

if [ "$choice" = B ]; then
  ui_print "B removes Google Play services, the Play Store,"
  ui_print "Google sign-in, Play Integrity and Google backup."
  ui_print "Volume Up = I'm sure, Volume Down = Cancel"
  [ "$(getkey "$TIMEOUT")" = up ] || abort "Cancelled - nothing installed"
  ui_print " "

  ui_print "Backing up Google Play services..."
  bk="$WL/backup-$(date +%Y%m%d-%H%M%S)"; rc=0
  mkdir -p "$bk" || rc=1
  for pkg in $UPDATED com.google.android.gsf; do
    mkdir -p "$bk/$pkg"
    for apk in $(pm path "$pkg" 2>/dev/null | sed -n 's/^package://p'); do
      cp -p "$apk" "$bk/$pkg/" || rc=1
    done
    for d in /data/data/$pkg /data/user_de/0/$pkg; do
      [ -d "$d" ] && { tar -czf "$bk/$pkg/$(echo "$d" | cut -d/ -f3).tgz" -C "$(dirname "$d")" "$pkg" 2>/dev/null || rc=1; }
    done
  done
  ui_print "  $bk"
  say_result $rc

  ui_print "Removing Google Play services..."
  whiteout $TRIM $FULL; rc=$?
  echo "$UPDATED" > "$WL/uninstall_updates"
  say_result $rc
else
  ui_print "Trimming Google telemetry..."
  whiteout $TRIM; say_result $?
fi

echo "$choice" > "$WL/choice"
case "$choice" in
  A) d="Choice A: Google stays, its location history, feedback and Go telemetry stubs are removed. Use Morphe Manager's root mount for patched apps." ;;
  B) d="Choice B: Google Play services and the Play Store are removed for microG. Install microG and signature spoofing as the README says. Disable this module to bring Google back." ;;
  C) d="Choice C: Google stays, its location history, feedback and Go telemetry stubs are removed. Run Morphe apps with MicroG-RE." ;;
esac
sed -i "s|^description=.*|description=$d|" "$MODPATH/module.prop"
ui_print " "
ui_print "Reboot to apply. README.md is in the module folder."
