#!/system/bin/sh
# Fixed, reviewed targets; no package-name wildcards or executable saved settings.
getkey() {
  local f="$MODPATH/.keys" answer=none count=0 pid
  : > "$f"
  getevent -lq > "$f" 2>/dev/null &
  pid=$!
  while [ "$count" -lt "$(( $1 * 10 ))" ]; do
    if grep -qE 'KEY_VOLUMEUP +DOWN' "$f"; then answer=up; break; fi
    if grep -qE 'KEY_VOLUMEDOWN +DOWN' "$f"; then answer=down; break; fi
    sleep 0.1
    count=$((count + 1))
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  rm -f "$f"
  echo "$answer"
}

setting() { awk -v key="$2" 'index($0, "=") && substr($0, 1, index($0, "=") - 1) == key { print substr($0, index($0, "=") + 1); exit }' "$1" 2>/dev/null; }
is_whiteout() { [ -c "$1" ]; }
previously_removed() {
  local path
  for path in $1; do is_whiteout "$ACTIVE/$path" && return 0; done
  return 1
}

probe() {
  CLASSPATH="$MODPATH/package-probe.dex" app_process /system/bin PackageProbe "$1"
}
trusted() {
  local pkg="$1" observation="$2" signers lineage known pin
  [ "$(setting "$observation" state)" = present ] || return 1
  signers=$(setting "$observation" signers)
  [ -n "$signers" ] || return 1
  grep -Fxq "$pkg|$signers" "$MODPATH/trusted-signers.txt" && return 0
  # Android verifies the proof of key rotation when parsing the actual APK.
  # Never accept a subset of a multi-signer identity as a rotation lineage.
  case "$signers" in *,*) return 1;; esac
  lineage=$(setting "$observation" lineage)
  while IFS='|' read -r known pin; do
    [ "$known" = "$pkg" ] || continue
    case "$pin" in *,*) continue;; esac
    case ",$lineage," in *",$pin,"*) return 0;; esac
  done < "$MODPATH/trusted-signers.txt"
  return 1
}

prepare_state() {
  [ ! -L "$WL" ] || return 1
  umask 077
  mkdir -p "$WL/backups" && chmod 700 "$WL" "$WL/backups"
}

backup_package() {
  local pkg="$1" observation="$2" fingerprint dest tmp apk index=0 data check
  fingerprint=$(setting "$observation" fingerprint)
  case "$fingerprint" in ''|*[!a-f0-9]*) return 1;; esac
  [ "${#fingerprint}" = 64 ] || return 1
  dest="$WL/backups/$pkg/$fingerprint"
  [ ! -L "$WL/backups/$pkg" ] && [ ! -L "$dest" ] || return 1
  [ -f "$dest/complete" ] && return 0
  mkdir -p "$WL/backups/$pkg" || return 1
  tmp="$dest.incomplete-$$"
  mkdir "$tmp" || return 1
  cp "$observation" "$tmp/package.txt" || return 1
  # Split APK names may repeat across split directories; use numbered filenames.
  sed -n 's/^apk=//p' "$observation" > "$tmp/apk-paths" || return 1
  while IFS= read -r apk; do
    case "$apk" in /data/app/*|/system/*|/product/*|/system_ext/*|/vendor/*) ;; *) return 1;; esac
    cp -p "$apk" "$tmp/$index.apk" || return 1
    [ "$(sha256sum "$apk" | cut -d ' ' -f 1)" = "$(sha256sum "$tmp/$index.apk" | cut -d ' ' -f 1)" ] || return 1
    index=$((index + 1))
  done < "$tmp/apk-paths"
  [ "$index" -gt 0 ] || return 1
  for data in /data/user/0 /data/user_de/0; do
    if [ -d "$data/$pkg" ]; then
      tar -czf "$tmp/$(basename "$data")-$(basename "$(dirname "$data")").tgz" -C "$data" "$pkg" || return 1
    fi
  done
  check="$tmp/recheck"
  probe "$pkg" > "$check" || return 1
  cmp -s "$observation" "$check" || return 1
  : > "$tmp/complete" || return 1
  mv "$tmp" "$dest"
}

real_path() {
  case "$1" in
    system/product/*) echo "/product/${1#system/product/}";;
    system/system_ext/*) echo "/system_ext/${1#system/system_ext/}";;
    system/vendor/*) echo "/vendor/${1#system/vendor/}";;
    system/*) echo "/$1";;
    *) return 1;;
  esac
}

cover_paths() {
  local path real count=0 present=0
  for path in $1; do
    real=$(real_path "$path") || return 1
    if [ -e "$real" ]; then present=$((present + 1)); fi
    mkdir -p "$MODPATH/$(dirname "$path")" || return 1
    if ! is_whiteout "$MODPATH/$path"; then
      mknod "$MODPATH/$path" c 0 0 || return 1
    fi
    chmod 644 "$MODPATH/$path" || return 1
    count=$((count + 1))
  done
  ui_print "Success! ($present present, $count paths covered across firmware)"
}

reset_overlay() {
  # Only discard generated staging content; never follow partition aliases.
  [ -n "$MODPATH" ] && [ "$MODPATH" != / ] && [ "$MODPATH" != "$ACTIVE" ] &&
    [ -f "$MODPATH/module.prop" ] || return 1
  rm -rf "$MODPATH/system" "$MODPATH/product" "$MODPATH/system_ext" "$MODPATH/vendor" || return 1
  rm -f "$MODPATH/face" "$MODPATH/lt" "$MODPATH/.package"
}

prepare_targets() {
  local pkg label paths hook observation="$MODPATH/.package"
  reset_overlay || return 1
  prepare_state || return 1
  while IFS='|' read -r pkg label paths hook; do
    [ -n "$pkg" ] || continue
    probe "$pkg" > "$observation" || return 1
    if [ "$(setting "$observation" state)" = present ]; then
      if trusted "$pkg" "$observation"; then
        backup_package "$pkg" "$observation" || return 1
      else
        ui_print "$label: replacement or unrecognized signer kept."
      fi
    fi
    ui_print "Covering $label..."
    cover_paths "$paths" || return 1
    case "$hook" in face|lt) : > "$MODPATH/$hook" || return 1;; esac
  done < "$MODPATH/selected-targets"
  rm -f "$observation"
}

cleanup_targets() {
  local pkg label paths hook before after base result version failed=0
  prepare_state || return 1
  before="$WL/.package-$$"; after="$WL/.recheck-$$"
  : > "$WL/cleanup-pending.next" || return 1
  while IFS='|' read -r pkg label paths hook; do
    [ -n "$pkg" ] || continue
    if ! probe "$pkg" > "$before"; then
      echo "$pkg: inspection failed" >> "$WL/cleanup-pending.next"; failed=1; continue
    fi
    [ "$(setting "$before" state)" = present ] || continue
    base=$(setting "$before" base)
    case "$base" in /data/app/*) ;; *)
      echo "$pkg: stock APK still visible; check mounting" >> "$WL/cleanup-pending.next"; failed=1; continue;;
    esac
    if ! trusted "$pkg" "$before"; then
      echo "$pkg: replacement or unrecognized signer kept"
      continue
    fi
    if ! backup_package "$pkg" "$before" || ! probe "$pkg" > "$after" || ! cmp -s "$before" "$after"; then
      echo "$pkg: backup or identity check failed" >> "$WL/cleanup-pending.next"; failed=1; continue
    fi
    version=$(setting "$before" version)
    case "$version" in ''|*[!0-9]*)
      echo "$pkg: missing version guard" >> "$WL/cleanup-pending.next"; failed=1; continue;;
    esac
    result=$(pm uninstall --versionCode "$version" "$pkg" 2>&1)
    echo "$pkg: $result"
    if ! probe "$pkg" > "$after" || [ "$(setting "$after" state)" != absent ]; then
      echo "$pkg: removal incomplete; retry next boot" >> "$WL/cleanup-pending.next"; failed=1
    fi
  done < "$MODPATH/selected-targets"
  mv "$WL/cleanup-pending.next" "$WL/cleanup-pending"
  rm -f "$before" "$after"
  return "$failed"
}
