#!/usr/bin/env bash
# Saves edits you made directly in chromium/src as a patch in patches/, so
# they survive ./update.sh and are re-applied on every Chromium version.
#
#   ./save-changes.sh "Short description"   save uncommitted edits as a new patch
#   ./save-changes.sh                       export commits you made yourself in src
#   ./save-changes.sh --list                show saved patches
#   ./save-changes.sh --discard             throw away unsaved edits in src
#
# To change a saved patch: edit patches/NNNN-*.patch, or delete it to drop
# that change. ./build.sh re-applies automatically.
source "$(dirname "$0")/scripts/common.sh"

require_src

if [[ "${1:-}" == "--list" ]]; then
  shopt -s nullglob
  for p in "$PATCHES_DIR"/*.patch; do
    printf '%s\n' "$(basename "$p")"
    sgit apply --numstat "$p" 2>/dev/null | awk '{printf "    %s (+%s -%s)\n", $3, $1, $2}'
  done
  exit 0
fi

if am_in_progress; then
  die "A patch is stopped on a conflict. Use ./apply.sh --continue instead."
fi
[[ -f "$(applied_marker)" ]] ||
  die "The customizations aren't fully applied. Run ./apply.sh first."

if [[ "${1:-}" == "--discard" ]]; then
  sgit status --short | head -30
  read -r -p "Discard these changes and any unsaved commits? [y/N] " answer
  [[ "$answer" == [yY]* ]] || exit 1
  sgit reset -q --hard "$(marker_field 2)"
  sgit clean -q -fd
  log "Discarded."
  exit 0
fi

if src_is_dirty; then
  [[ -n "${1:-}" ]] || die "Describe the change: ./save-changes.sh \"Make tabs rounder\""
  sgit add -A
  sgit commit -q -m "$1"
fi

export_patches
write_marker
log "Saved. Patches in patches/:"
ls -1 "$PATCHES_DIR" | grep '\.patch$' | sed 's/^/    /' || echo "    (none)"
