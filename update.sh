#!/usr/bin/env bash
# Moves NeoWeb onto a newer Chromium release, keeping every customization:
# branding and icons are regenerated, and patches/ is re-applied on top.
#
#   ./update.sh                     latest release of CHROMIUM_CHANNEL, then build
#   ./update.sh --check             only show whether an update is available
#   ./update.sh --version X.Y.Z.W   a specific version (also to roll back)
#   ./update.sh --no-build          don't build afterwards
#   ./update.sh --force             re-sync even if already on that version
source "$(dirname "$0")/scripts/common.sh"

version=""
build=1
check=0
force=0
while (($#)); do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --no-build) build=0; shift ;;
    --check) check=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_src
current="$(current_version || true)"
if [[ -z "$version" ]]; then
  version="$(latest_version)" || die "Could not look up the latest Chromium version."
fi

if ((check)); then
  if [[ "$version" == "$current" ]]; then
    log "Up to date: Chromium $current ($CHROMIUM_CHANNEL)"
  else
    log "Update available: $current -> $version ($CHROMIUM_CHANNEL). Run ./update.sh"
  fi
  exit 0
fi

if [[ "$version" == "$current" ]] && ((!force)); then
  log "Already on Chromium $current. (Use --force to re-sync anyway.)"
  exit 0
fi

# Nothing may be lost: uncommitted edits or unsaved commits stop the update.
ensure_nothing_unsaved

log "Updating depot_tools"
DEPOT_TOOLS_UPDATE=1 "$DEPOT_TOOLS/update_depot_tools" >/dev/null 2>&1 ||
  warn "Could not update depot_tools; continuing with the current one."

fetch_chromium_tag "$version"

# Switch to the new pristine release before syncing, so gclient reads the
# new version's DEPS. Customizations are re-applied by apply.sh below.
rm -f "$(applied_marker)"
sgit tag -f "$BASE_TAG" "$version^{commit}" >/dev/null
sgit checkout -q -B "$BRANCH" "$BASE_TAG"
echo "$version" >"$VERSION_FILE"

log "Syncing dependencies for $version (gclient sync)"
(cd "$CHROMIUM_DIR" && gclient sync -D --no-history --shallow --force)

"$NEOWEB_ROOT/apply.sh"

log "NeoWeb is now based on Chromium $version (was ${current:-unknown})."
if ((build)); then
  "$NEOWEB_ROOT/build.sh"
fi
