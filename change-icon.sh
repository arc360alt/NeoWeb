#!/usr/bin/env bash
# Changes NeoWeb's icon everywhere: app icon, window/taskbar icon, about page,
# favicons, tray icon, Windows .ico and the desktop launcher.
#
#   ./change-icon.sh new-icon.svg          use a new SVG, then rebuild
#   ./change-icon.sh                       re-apply after editing branding/icon.svg
#   ./change-icon.sh new-icon.svg --no-build
#
# The icon must be an SVG (square works best; it's rendered at every size
# from 16 px to 1024 px). The previous icon is kept in branding/icon-history/.
# Preview renders are written to branding/preview/.
source "$(dirname "$0")/scripts/common.sh"

new=""
build=1
while (($#)); do
  case "$1" in
    --no-build) build=0; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) new="$1"; shift ;;
  esac
done

icon="$NEOWEB_ROOT/branding/icon.svg"
icons_py=(python3 "$NEOWEB_ROOT/scripts/lib/icons.py" --name "$BROWSER_NAME")

if [[ -n "$new" ]]; then
  [[ -f "$new" ]] || die "File not found: $new"
  [[ "${new,,}" == *.svg ]] || die "The icon must be an .svg file."
  "${icons_py[@]}" --svg "$new" --validate
  if [[ -f "$icon" ]] && ! cmp -s "$new" "$icon"; then
    mkdir -p "$NEOWEB_ROOT/branding/icon-history"
    backup="$NEOWEB_ROOT/branding/icon-history/icon-$(date +%Y%m%d-%H%M%S).svg"
    cp "$icon" "$backup"
    log "Previous icon saved to ${backup#"$NEOWEB_ROOT"/}"
  fi
  [[ "$(realpath "$new")" == "$(realpath "$icon")" ]] || cp "$new" "$icon"
fi
[[ -f "$icon" ]] || die "No icon at branding/icon.svg."

rm -rf "$NEOWEB_ROOT/branding/preview"
"${icons_py[@]}" --svg "$icon" --preview "$NEOWEB_ROOT/branding/preview"

if [[ -f "$HOME/.local/share/applications/${BROWSER_ID}.desktop" ]]; then
  "$NEOWEB_ROOT/install-desktop.sh"
fi

if [[ ! -d "$SRC/.git" ]]; then
  log "Icon set. It will be used when you run ./setup.sh."
elif ((build)); then
  "$NEOWEB_ROOT/build.sh"
else
  log "Icon set. Run ./build.sh to put it in the browser."
fi
