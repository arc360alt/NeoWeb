# Shared helpers for the NeoWeb scripts. Source this file; don't run it.

set -euo pipefail

NEOWEB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../neoweb.conf
source "$NEOWEB_ROOT/neoweb.conf"

DEPOT_TOOLS="$NEOWEB_ROOT/depot_tools"
CHROMIUM_DIR="$NEOWEB_ROOT/chromium"
SRC="$CHROMIUM_DIR/src"
OUT="$SRC/$OUT_DIR"
PATCHES_DIR="$NEOWEB_ROOT/patches"
VERSION_FILE="$NEOWEB_ROOT/chromium_version.txt"

# Git refs NeoWeb keeps inside the Chromium checkout:
#   neoweb-base      the untouched upstream Chromium release
#   neoweb-branding  base + generated branding (name, icons, theme, strings)
#   branch "neoweb"  neoweb-branding + one commit per file in patches/
BASE_TAG="neoweb-base"
BRANDING_TAG="neoweb-branding"
BRANCH="neoweb"

export PATH="$DEPOT_TOOLS:$PATH"
# depot_tools is updated explicitly by setup.sh / update.sh, not mid-build.
export DEPOT_TOOLS_UPDATE="${DEPOT_TOOLS_UPDATE:-0}"

if [[ -t 1 ]]; then
  C_BLUE=$'\e[1;36m' C_YELLOW=$'\e[1;33m' C_RED=$'\e[1;31m' C_OFF=$'\e[0m'
else
  C_BLUE="" C_YELLOW="" C_RED="" C_OFF=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

sgit() { git -C "$SRC" "$@"; }

require_src() {
  [[ -d "$SRC/.git" ]] || die "Chromium source not found at $SRC. Run ./setup.sh first."
  command -v gclient >/dev/null || die "depot_tools missing. Run ./setup.sh first."
}

current_version() {
  [[ -f "$VERSION_FILE" ]] && tr -d '[:space:]' <"$VERSION_FILE"
}

# Latest Chromium version for the configured channel (Linux).
latest_version() {
  local url="https://versionhistory.googleapis.com/v1/chrome/platforms/linux/channels/${CHROMIUM_CHANNEL}/versions?pageSize=1"
  curl -fsSL "$url" | python3 -c 'import json,sys; print(json.load(sys.stdin)["versions"][0]["version"])'
}

# Where Chromium's source is downloaded from, in order. Google's server
# sometimes stalls on big downloads; GitHub hosts an official mirror.
CHROMIUM_GIT_URLS=(
  "https://chromium.googlesource.com/chromium/src.git"
  "https://github.com/chromium/chromium.git"
)

# Downloads one Chromium release tag (no history) into $SRC, trying each
# mirror in turn. A mirror that sends nothing for 3 minutes counts as stalled.
fetch_chromium_tag() {
  local version="$1" url
  [[ -d "$SRC/.git" ]] || git init -q "$SRC"
  for url in "${CHROMIUM_GIT_URLS[@]}"; do
    sgit remote remove origin 2>/dev/null || true
    sgit remote add origin "$url"
    log "Downloading Chromium $version from ${url#https://}"
    if sgit -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=180 \
        fetch --depth 1 --no-tags --progress origin \
        "+refs/tags/$version:refs/tags/$version"; then
      return 0
    fi
    warn "Download from ${url#https://} failed or stalled; trying the next mirror."
  done
  die "Could not download Chromium $version. Check your connection and version number, then re-run."
}

# True if the Chromium checkout has edits that aren't committed yet.
src_is_dirty() {
  [[ -n "$(sgit status --porcelain --untracked-files=normal)" ]]
}

# True while a `git am` (patch apply) is stopped on a conflict.
am_in_progress() {
  [[ -d "$(sgit rev-parse --absolute-git-dir)/rebase-apply" ]]
}

# Marker written once every patch in patches/ has been applied. Without it the
# branch may be missing patches, and exporting would delete them from patches/.
applied_marker() { echo "$(sgit rev-parse --absolute-git-dir)/neoweb-applied"; }

# Fingerprint of everything that feeds ./apply.sh. Build-only settings are left
# out so changing them doesn't force a re-apply (and a large rebuild).
inputs_hash() {
  (
    cd "$NEOWEB_ROOT"
    grep -vE '^(BUILD_JOBS|OUT_DIR|CHROMIUM_CHANNEL)=' neoweb.conf
    cat chromium_version.txt 2>/dev/null || true
    find branding patches scripts/lib -type f \
      ! -path 'branding/preview/*' ! -path 'branding/icon-history/*' \
      ! -path '*/__pycache__/*' -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum | cut -d' ' -f1
}

# Records that the checkout matches the current inputs: "<inputs hash> <HEAD>".
write_marker() {
  echo "$(inputs_hash) $(sgit rev-parse HEAD)" >"$(applied_marker)"
}

marker_field() {  # 1 = inputs hash, 2 = HEAD commit
  local m
  m="$(applied_marker)"
  [[ -f "$m" ]] && cut -d' ' -f"$1" "$m"
}

needs_apply() {
  [[ "$(marker_field 1)" != "$(inputs_hash)" ]]
}

# Write every commit on top of the branding commit out to patches/, so
# custom source changes live in the NeoWeb folder and survive updates.
export_patches() {
  sgit rev-parse -q --verify "refs/tags/$BRANDING_TAG" >/dev/null || return 0
  [[ -f "$(applied_marker)" ]] ||
    die "Not all patches are applied in the Chromium checkout. Run ./apply.sh first."
  [[ "$(sgit rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] ||
    die "Chromium checkout is not on the '$BRANCH' branch; not exporting patches."
  local tmp
  tmp="$(mktemp -d)"
  sgit format-patch --quiet --no-signature --zero-commit --no-stat \
    -o "$tmp" "$BRANDING_TAG..HEAD"
  rm -f "$PATCHES_DIR"/*.patch
  if compgen -G "$tmp/*.patch" >/dev/null; then
    mv "$tmp"/*.patch "$PATCHES_DIR/"
  fi
  rmdir "$tmp"
}

# Refuse to throw away anything that isn't saved in patches/.
ensure_nothing_unsaved() {
  if am_in_progress; then
    die "A patch is stopped on a conflict. Fix it (see ./apply.sh output), then run ./apply.sh --continue."
  fi
  if src_is_dirty; then
    sgit status --short | head -20 >&2
    die "The Chromium checkout has unsaved changes (above). Run ./save-changes.sh \"description\" to keep them, or ./save-changes.sh --discard to drop them."
  fi
  local head
  head="$(marker_field 2 || true)"
  if [[ -n "$head" && "$head" != "$(sgit rev-parse HEAD)" ]]; then
    die "The Chromium checkout has commits that aren't in patches/ yet. Run ./save-changes.sh to keep them."
  fi
}
