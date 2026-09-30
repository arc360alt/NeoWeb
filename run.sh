#!/usr/bin/env bash
# Starts the latest NeoWeb build. Extra arguments go to the browser.
#
#   ./run.sh                      open NeoWeb
#   ./run.sh --build              build first (only rebuilds what changed)
#   ./run.sh --temp-profile       use a throwaway profile (for testing)
#   ./run.sh https://example.com  open a page
source "$(dirname "$0")/scripts/common.sh"

args=()
for arg in "$@"; do
  case "$arg" in
    --build) "$NEOWEB_ROOT/build.sh" ;;
    --temp-profile)
      profile="$(mktemp -d -t neoweb-profile.XXXXXX)"
      args+=("--user-data-dir=$profile")
      log "Temporary profile: $profile"
      ;;
    *) args+=("$arg") ;;
  esac
done

binary="$OUT/chrome"
[[ -x "$binary" ]] || die "No build found at $binary. Run ./build.sh first."

# Ties the window to neoweb.desktop so docks and taskbars show NeoWeb's icon.
export CHROME_DESKTOP="${BROWSER_ID}.desktop"
# Hides the "Google API keys are missing" bar; NeoWeb doesn't use Google's
# sign-in/sync services.
export GOOGLE_API_KEY="${GOOGLE_API_KEY:-no}"
export GOOGLE_DEFAULT_CLIENT_ID="${GOOGLE_DEFAULT_CLIENT_ID:-no}"
export GOOGLE_DEFAULT_CLIENT_SECRET="${GOOGLE_DEFAULT_CLIENT_SECRET:-no}"

exec "$binary" "${args[@]}"
