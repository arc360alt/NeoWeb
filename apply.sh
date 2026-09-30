#!/usr/bin/env bash
# Rebuilds the NeoWeb source tree from scratch: resets the Chromium checkout to
# the pristine release, then applies branding (neoweb.conf, branding/) and
# every patch in patches/, in order.
#
#   ./apply.sh              apply everything (build.sh does this when needed)
#   ./apply.sh --continue   finish after fixing a patch that didn't apply
#   ./apply.sh --skip       drop a patch that didn't apply (removes it from patches/)
#   ./apply.sh --abort      stop; patches/ is left unchanged
source "$(dirname "$0")/scripts/common.sh"

conflict_help() {
  cat >&2 <<EOF

${C_YELLOW}A patch no longer applies cleanly to this Chromium version.${C_OFF}
This happens when Chromium changed the same code. Your patch files are safe.

  1. Look at the conflicting files:   git -C "$SRC" status
     Edit them so they contain your change on top of the new code
     (remove the <<<<<<< ======= >>>>>>> markers).
  2. Run: ./apply.sh --continue
     patches/ is then refreshed with the fixed patch.

To drop that patch instead:  ./apply.sh --skip   (deletes it from patches/)
To stop for now:             ./apply.sh --abort  (patches/ stays unchanged)
EOF
  exit 1
}

finish() {
  write_marker
  export_patches
  write_marker  # patch files may be rewritten byte-for-byte; re-record.
  local n
  n=$(sgit rev-list --count "$BRANDING_TAG..HEAD")
  log "NeoWeb customizations applied ($n patch(es) on Chromium $(current_version))."
}

run_am() {
  sgit am --3way --keep-cr --whitespace=nowarn "$@" || conflict_help
}

require_src

case "${1:-}" in
  --continue)
    am_in_progress || die "No patch is waiting to be continued."
    sgit add -A
    run_am --continue
    finish
    exit 0
    ;;
  --skip)
    am_in_progress || die "No patch is waiting to be skipped."
    run_am --skip
    finish
    exit 0
    ;;
  --abort)
    am_in_progress && sgit am --abort
    log "Aborted. Run ./apply.sh to start over."
    exit 0
    ;;
  "") ;;
  *) die "Unknown option: $1" ;;
esac

ensure_nothing_unsaved
sgit rev-parse -q --verify "refs/tags/$BASE_TAG" >/dev/null ||
  die "Tag $BASE_TAG missing in the Chromium checkout. Run ./setup.sh."

# Commits are authored by you when git knows your name, otherwise "NeoWeb".
sgit config user.email >/dev/null || sgit config user.email "neoweb@localhost"
sgit config user.name >/dev/null || sgit config user.name "NeoWeb"

log "Resetting Chromium to the pristine $(current_version) release"
rm -f "$(applied_marker)"
sgit checkout -q -B "$BRANCH" "$BASE_TAG"

log "Applying branding, strings, theme and icons"
python3 "$NEOWEB_ROOT/scripts/lib/customize.py" --src "$SRC"
sgit add -A
sgit commit -q --allow-empty -m "NeoWeb: generated branding" \
  -m "Created by apply.sh from neoweb.conf and branding/. Do not edit; it is regenerated."
sgit tag -f "$BRANDING_TAG" >/dev/null

shopt -s nullglob
patches=("$PATCHES_DIR"/*.patch)
if ((${#patches[@]})); then
  log "Applying ${#patches[@]} patch(es) from patches/"
  run_am "${patches[@]}"
fi
finish
