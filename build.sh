#!/usr/bin/env bash
# Builds NeoWeb. Re-applies customizations first if neoweb.conf, branding/ or
# patches/ changed since the last apply.
#
#   ./build.sh                build the browser
#   ./build.sh -j 8           limit parallel jobs (overrides BUILD_JOBS)
#   ./build.sh --clean        delete the build output first (full rebuild)
#   ./build.sh [targets...]   build other ninja targets (default: chrome)
source "$(dirname "$0")/scripts/common.sh"

jobs="$BUILD_JOBS"
clean=0
targets=()
while (($#)); do
  case "$1" in
    -j) jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    --clean) clean=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) targets+=("$1"); shift ;;
  esac
done
((${#targets[@]})) || targets=(chrome)

require_src

if am_in_progress; then
  die "A patch is stopped on a conflict. Finish it with ./apply.sh --continue first."
fi
if needs_apply; then
  log "NeoWeb customizations changed; re-applying"
  "$NEOWEB_ROOT/apply.sh"
fi

if ((clean)); then
  log "Removing $OUT"
  rm -rf "$OUT"
fi

mkdir -p "$OUT"
if ! cmp -s "$NEOWEB_ROOT/config/args.gn" "$OUT/args.gn"; then
  cp "$NEOWEB_ROOT/config/args.gn" "$OUT/args.gn"
fi

cd "$SRC"
log "Generating build files ($OUT_DIR)"
gn gen "$OUT_DIR"

log "Building ${targets[*]} (this takes hours the first time)"
ninja_args=(-C "$OUT_DIR")
[[ -n "$jobs" ]] && ninja_args+=(-j "$jobs")
start=$SECONDS
autoninja "${ninja_args[@]}" "${targets[@]}"

log "Build finished in $(((SECONDS - start) / 60)) min. Start it with ./run.sh"
