ui_print "Degoogler CyberspaceVII"
ui_print " "
reuse=no
if [ -d "$ACTIVE" ]; then
  ui_print "Keep previous choices? Up = keep, Down = choose again (keep after 10s)."
  [ "$(getkey 10)" = down ] || reuse=yes
fi
if [ "$reuse" = yes ]; then
  choice=$(setting "$ACTIVE/selections" choice)
  case "$choice" in
    A|B|C) ;;
    *)
      if previously_removed system/product/priv-app/GmsCoreGo; then choice=B
      else
        choice=$(cat "$WL/choice" 2>/dev/null)
        case "$choice" in A|C) ;; *) choice=A;; esac
      fi;;
  esac
else
  names="A. Keep Google, trim telemetry (Morphe root mount)
B. Replace Google services with microG
C. Keep Google, trim telemetry (Morphe + MicroG-RE)
Cancel - install nothing"
  ui_print "Down = next, Up = select (cancel after 30s)."
  index=1
  while :; do
    ui_print "> $(echo "$names" | sed -n "${index}p")"
    case "$(getkey 30)" in
      down) index=$((index % 4 + 1));;
      up) break;;
      *) abort "Cancelled - existing choices kept.";;
    esac
  done
  case "$index" in 1) choice=A;; 2) choice=B;; 3) choice=C;; *) abort "Cancelled - existing choices kept.";; esac
  if [ "$choice" = B ]; then
    ui_print "Remove Google services, Store, backup, intelligence and Android Auto?"
    ui_print "Up = confirm, Down or timeout = cancel. Read the README first."
    [ "$(getkey 30)" = up ] || abort "Cancelled - existing choices kept."
  fi
fi
intelligence=no; auto=no
if [ "$choice" = B ]; then
  intelligence=yes; auto=yes
elif [ "$reuse" = yes ]; then
  [ "$(setting "$ACTIVE/selections" intelligence)" = yes ] && intelligence=yes
  [ "$(setting "$ACTIVE/selections" auto)" = yes ] && auto=yes
else
  ui_print "Remove on-device intelligence and Private Compute Services?"
  ui_print "Loses smart text, predictions, captions and related features."
  ui_print "Up = remove, Down or timeout = keep."
  [ "$(getkey 10)" = up ] && intelligence=yes
  ui_print "Remove Android Auto? Up = remove, Down or timeout = keep."
  [ "$(getkey 10)" = up ] && auto=yes
fi
printf 'choice=%s\nintelligence=%s\nauto=%s\n' "$choice" "$intelligence" "$auto" > "$MODPATH/selections"
: > "$MODPATH/selected-targets"
while IFS='|' read -r pkg label paths group; do
  selected=no
  case "$group" in
    trim) selected=yes;;
    full) [ "$choice" = B ] && selected=yes;;
    intelligence) selected=$intelligence;;
    auto) selected=$auto;;
  esac
  [ "$selected" = yes ] && echo "$pkg|$label|$paths|" >> "$MODPATH/selected-targets"
done < "$MODPATH/targets.txt"
prepare_targets || abort "Fail! Could not back up or cover a selected app; existing choices kept."
case "$choice" in
  B) description="Google services are replaced for microG; intelligence and Android Auto are removed. Read the README for setup and restoration.";;
  *) description="Google stays with telemetry trimmed. Intelligence and Android Auto follow your optional choices. Disable and reboot to restore stock apps.";;
esac
sed -i "s|^description=.*|description=$description|" "$MODPATH/module.prop" || abort "Fail! Could not save description."
ui_print "Choice $choice; intelligence removal: $intelligence; Android Auto removal: $auto."
ui_print "Reboot to apply. Backups stay available after removal."
