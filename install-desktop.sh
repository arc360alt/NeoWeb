#!/usr/bin/env bash
# Adds NeoWeb to your app launcher/menu (for the current user) with its icon.
#
#   ./install-desktop.sh              install or refresh
#   ./install-desktop.sh --uninstall  remove
source "$(dirname "$0")/scripts/common.sh"

apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor"
desktop="$apps/${BROWSER_ID}.desktop"
sizes=(16 24 32 48 64 128 256 512)

refresh_caches() {
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$apps" || true
  # Only refresh an existing per-user icon cache; creating one can hide icons
  # that other apps install later.
  if [[ -f "$icons/icon-theme.cache" ]] && command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -t "$icons" || true
  fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$desktop" "$icons/scalable/apps/${BROWSER_ID}.svg"
  for s in "${sizes[@]}"; do rm -f "$icons/${s}x${s}/apps/${BROWSER_ID}.png"; done
  refresh_caches
  log "Removed $BROWSER_NAME from the app menu."
  exit 0
fi

for s in "${sizes[@]}"; do
  mkdir -p "$icons/${s}x${s}/apps"
  rsvg-convert -w "$s" -h "$s" -a -o "$icons/${s}x${s}/apps/${BROWSER_ID}.png" \
    "$NEOWEB_ROOT/branding/icon.svg"
done
mkdir -p "$icons/scalable/apps" "$apps"
cp "$NEOWEB_ROOT/branding/icon.svg" "$icons/scalable/apps/${BROWSER_ID}.svg"

cat >"$desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$BROWSER_NAME
GenericName=Web Browser
Comment=Browse the web with $BROWSER_NAME
Exec="$NEOWEB_ROOT/run.sh" %U
Icon=$BROWSER_ID
Terminal=false
StartupNotify=true
StartupWMClass=$BROWSER_ID
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec="$NEOWEB_ROOT/run.sh"

[Desktop Action new-private-window]
Name=New Incognito Window
Exec="$NEOWEB_ROOT/run.sh" --incognito
EOF
refresh_caches
log "$BROWSER_NAME added to the app menu ($desktop)."
