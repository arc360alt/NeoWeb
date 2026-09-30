# NeoWeb

A Chromium-based browser with its own name, icon and cyan default theme, plus
scripts to build it, run it, and move it to new Chromium releases without
losing any customization.

Linux (x86-64) is the supported build platform.

## Quick start

```bash
./setup.sh           # once: deps, depot_tools, Chromium source (~35 GB download)
./build.sh           # first build takes hours; later builds are incremental
./run.sh             # start NeoWeb
./install-desktop.sh # optional: add NeoWeb to your app menu
```

Requirements: ~100 GB free disk space, 16 GB+ RAM (32 GB recommended), and
`git`, `python3`, `curl`, `rsvg-convert` (librsvg) and ImageMagick.
`setup.sh` installs these on Arch, Fedora and Debian/Ubuntu.

## Scripts

| Script | What it does |
|---|---|
| `./setup.sh` | One-time setup. `--version X` picks a Chromium version, `--skip-deps` skips system packages. |
| `./build.sh` | Builds NeoWeb. Re-applies your customizations first if anything in `neoweb.conf`, `branding/` or `patches/` changed. `-j N` limits jobs, `--clean` does a full rebuild. |
| `./run.sh` | Runs the latest build. `--build` builds first, `--temp-profile` uses a throwaway profile, other arguments go to the browser. |
| `./update.sh` | Moves to the newest Chromium release of `CHROMIUM_CHANNEL`, re-applies everything, then builds. `--check` only checks, `--version X` picks (or rolls back to) a version, `--no-build` skips the build. |
| `./change-icon.sh new.svg` | Replaces the icon everywhere, then rebuilds. Run with no argument after editing `branding/icon.svg` directly. |
| `./save-changes.sh "note"` | Saves code edits you made in `chromium/src` as a patch in `patches/`. |
| `./apply.sh` | Re-applies all customizations to a clean Chromium tree. `build.sh` and `update.sh` call it for you. |
| `./install-desktop.sh` | Adds a NeoWeb launcher and icon to your app menu (`--uninstall` removes it). |

## How customizations survive updates

`chromium/src` is disposable. Everything that makes NeoWeb *NeoWeb* lives
outside it, and `apply.sh` re-creates the browser's source from scratch on top
of a clean Chromium release:

1. **`neoweb.conf`**: name, company, profile folder id, theme color.
2. **`branding/icon.svg`**: the master icon. Every Chromium logo (window,
   taskbar, about page, favicons, tray, Windows `.ico`, wordmarks) is re-rendered
   from it at the size the original file had.
3. **`branding/strings.conf`**: text replacements for UI strings. "Chromium"
   becomes "NeoWeb" in every language; translations are re-keyed so they keep
   working.
4. **`patches/`**: any other code change, as git patches applied in order.

Because steps 1–3 are search-and-replace rather than line-number diffs, they
keep working when Chromium moves code around. If Chromium changes code a patch
touches, `update.sh` stops and explains how to fix it. Your patch files are
never overwritten until the fix is saved. If something in steps 1–3 can't be
found in a new version, you get a warning naming it.

### Making your own changes

- **Name, colors:** edit `neoweb.conf`, then `./build.sh`.
- **Text:** add `Find => Replace` lines to `branding/strings.conf`.
- **Icon:** `./change-icon.sh my-icon.svg`. The old one is kept in
  `branding/icon-history/` and preview PNGs go to `branding/preview/`.
- **Anything else (code, UI, features):** edit files in `chromium/src`, test
  with `./build.sh && ./run.sh`, then run
  `./save-changes.sh "What I changed"`. `apply.sh` and `update.sh` refuse to
  run while you have unsaved edits, so nothing gets lost by accident. To
  remove a change, delete its file from `patches/`.

Edits inside Chromium's sub-repositories (`chromium/src/v8`,
`chromium/src/third_party/...`) aren't captured by `save-changes.sh`.

### When an update hits a conflict

```
./update.sh
# "A patch no longer applies cleanly" → open the listed files, merge your change
# into the new code (remove the <<<<<<< ======= >>>>>>> markers), then:
./apply.sh --continue
./build.sh
```

`./apply.sh --skip` drops that patch. `./update.sh --version <old version>`
goes back to the previous Chromium.

## Theme

New profiles start with a Material "dynamic color" theme seeded from
`THEME_COLOR` (default `#00E8DA`, the icon's cyan) using the `THEME_VARIANT`
style. Users can still choose another color (or Chromium's original grey) in
the Customize side panel. On Linux, new profiles use this theme
instead of GTK colors (`DEFAULT_TO_CLASSIC_THEME`).

Existing profiles keep the theme they already have.

## Details

- Profile data: `~/.config/neoweb` (separate from any installed Chromium).
- Build settings: `config/args.gn` (release build, proprietary codecs).
- Google sign-in/sync isn't available: that needs Google API keys, which
  Chromium forks can't ship. `run.sh` hides the "API keys missing" warning.
- The macOS `.icns` icon is only regenerated when `png2icns` (libicns) is
  installed. It's only used by macOS builds.
- The Chromium license requires keeping "The Chromium Authors" copyright
  notice, so the default `COPYRIGHT` keeps it next to NeoWeb.
