#!/usr/bin/env python3
"""Regenerates every Chromium logo file from one master SVG.

Each target is rendered straight from the vector source at the size the
existing file already has, so new Chromium versions that add or resize logos
are handled without changes here.

Needs rsvg-convert (librsvg) and ImageMagick 7 (`magick`).
"""

import argparse
import base64
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

# (glob relative to the Chromium src dir, how to regenerate it)
#   raster   PNG/XPM at the existing file's size (style picked from its name)
#   svg      copy of the master SVG
#   ico      multi-size Windows icon
#   icns     macOS icon (best effort; only needed for macOS builds)
TARGETS = [
    ("chrome/app/theme/chromium/product_logo_*.png", "raster"),
    ("chrome/app/theme/chromium/linux/product_logo_*.png", "raster"),
    ("chrome/app/theme/chromium/linux/product_logo_*.xpm", "raster"),
    ("chrome/app/theme/default_*_percent/chromium/product_logo*.png", "raster"),
    ("chrome/app/theme/default_*_percent/chromium/linux/product_logo_*.png", "raster"),
    ("components/resources/default_*_percent/chromium/product_logo*.png", "raster"),
    ("components/resources/default_*_percent/chromium/favicon_product.png", "raster"),
    ("chrome/app/theme/chromium/win/tiles/*.png", "raster"),
    ("chrome/app/theme/chromium/mac/Assets.xcassets/*/*.png", "raster"),
    ("chrome/app/theme/chromium/product_logo.svg", "svg"),
    ("chrome/app/theme/chromium/product_logo_animation.svg", "svg"),
    ("chrome/app/theme/chromium/win/chromium.ico", "ico"),
    ("chrome/app/theme/chromium/win/app_list.ico", "ico"),
    ("chrome/app/theme/chromium/mac/app.icns", "icns"),
]

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
ICNS_SIZES = [16, 32, 128, 256, 512]
MONO_COLOR = "#5F6368"
WORDMARK_TEXT_COLOR = "#3C4043"


# ImageMagick 7 is `magick`; ImageMagick 6 (e.g. Ubuntu) is `convert`.
MAGICK = "magick" if shutil.which("magick") else "convert"
IDENTIFY = ["magick", "identify"] if MAGICK == "magick" else ["identify"]


def run(*cmd):
    if cmd[0] == "magick":
        cmd = (MAGICK,) + cmd[1:]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def query(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def image_size(path):
    w, h = query(*IDENTIFY, "-format", "%w %h", f"{path}[0]").split()
    return int(w), int(h)


def render_svg(svg, size, out_png):
    run("rsvg-convert", "-w", str(size), "-h", str(size), "-a",
        "-o", out_png, svg)


def render_icon(svg, width, height, out, style, tmp):
    """Icon centered on a transparent width x height canvas."""
    side = min(width, height)
    png = os.path.join(tmp, f"icon_{side}.png")
    render_svg(svg, side, png)
    cmd = ["magick", "-size", f"{width}x{height}", "xc:none", png,
           "-gravity", "center", "-composite"]
    if style == "white":
        cmd += ["-fill", "white", "-colorize", "100"]
    elif style == "mono":
        cmd += ["-fill", MONO_COLOR, "-colorize", "100"]
    run(*cmd, "-strip", out)


def render_wordmark(svg, height, name, out, text_color, tmp):
    """Icon followed by the browser name, e.g. product_logo_name_22.png."""
    with open(svg, "rb") as f:
        icon_uri = "data:image/svg+xml;base64," + base64.b64encode(f.read()).decode()
    font = height * 0.68
    gap = height * 0.3
    width = round(height + gap + font * 0.62 * len(name) + 2)
    wrapper = f"""<svg xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <image x="0" y="0" width="{height}" height="{height}" xlink:href="{icon_uri}"/>
  <text x="{height + gap}" y="{height / 2}" dominant-baseline="central"
        font-family="Google Sans, Roboto, Segoe UI, Noto Sans, DejaVu Sans, sans-serif"
        font-size="{font}" font-weight="500" fill="{text_color}">{escape(name)}</text>
</svg>"""
    wrapper_path = os.path.join(tmp, "wordmark.svg")
    with open(wrapper_path, "w") as f:
        f.write(wrapper)
    png = os.path.join(tmp, "wordmark.png")
    run("rsvg-convert", "-o", png, wrapper_path)
    # Drop unused space on the right; keep the full height.
    bbox = query(*IDENTIFY, "-format", "%@", png)  # e.g. "90x20+0+1"
    m = re.match(r"(\d+)x\d+\+(\d+)\+", bbox)
    right = int(m.group(1)) + int(m.group(2)) + 1 if m else width
    run("magick", png, "-crop", f"{min(right, width)}x{height}+0+0", "+repage",
        "-strip", out)


def raster_style(basename, width, height):
    # Wide images are wordmarks (icon + product name), e.g. product_logo_name_22.
    if "_name_" in basename or width > 1.5 * height:
        return "wordmark_white" if "white" in basename else "wordmark"
    if "white" in basename:
        return "white"
    if "mono" in basename:
        return "mono"
    return "color"


def make_raster(svg, path, name, tmp):
    width, height = image_size(path)
    style = raster_style(os.path.basename(path), width, height)
    if style.startswith("wordmark"):
        color = "#FFFFFF" if style == "wordmark_white" else WORDMARK_TEXT_COLOR
        render_wordmark(svg, height, name, path, color, tmp)
    else:
        render_icon(svg, width, height, path, style, tmp)


def make_multi(svg, path, sizes, tmp):
    pngs = []
    for size in sizes:
        png = os.path.join(tmp, f"multi_{size}.png")
        render_svg(svg, size, png)
        pngs.append(png)
    if not path.endswith(".icns"):
        run("magick", *pngs, path)
    elif shutil.which("png2icns"):  # from libicns
        run("png2icns", path, *pngs)
    else:
        # ImageMagick can't write .icns. Leave the file alone rather than
        # corrupt it; it's only used by macOS builds.
        raise subprocess.CalledProcessError(1, "png2icns")


def replace_all(svg, src, name):
    done, failed = 0, []
    with tempfile.TemporaryDirectory() as tmp:
        for pattern, kind in TARGETS:
            for path in sorted(glob.glob(os.path.join(src, pattern))):
                rel = os.path.relpath(path, src)
                try:
                    if kind == "svg":
                        shutil.copyfile(svg, path)
                    elif kind == "ico":
                        make_multi(svg, path, ICO_SIZES, tmp)
                    elif kind == "icns":
                        make_multi(svg, path, ICNS_SIZES, tmp)
                    else:
                        make_raster(svg, path, name, tmp)
                    done += 1
                except subprocess.CalledProcessError:
                    failed.append(rel)
    print(f"    icons: regenerated {done} files")
    for rel in failed:
        if rel.endswith(".icns"):
            # Only macOS builds use it, so it doesn't fail the run.
            print(f"    icons: skipped {rel} (install libicns to regenerate it)")
        else:
            print(f"    icons: WARNING could not regenerate {rel}", file=sys.stderr)
    return done > 0 and not any(not f.endswith(".icns") for f in failed)


def preview(svg, out_dir, name):
    """Writes sample renders so a new icon can be checked before building."""
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for size in (16, 32, 48, 128, 256):
            render_svg(svg, size, os.path.join(out_dir, f"icon_{size}.png"))
        render_icon(svg, 22, 22, os.path.join(out_dir, "tray_mono_22.png"), "mono", tmp)
        render_wordmark(svg, 44, name, os.path.join(out_dir, "wordmark_44.png"),
                        WORDMARK_TEXT_COLOR, tmp)
    print(f"    icons: preview written to {out_dir}")


def validate(svg):
    with tempfile.TemporaryDirectory() as tmp:
        render_svg(svg, 64, os.path.join(tmp, "test.png"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--svg", required=True, help="master icon SVG")
    parser.add_argument("--name", default="NeoWeb", help="browser name for wordmarks")
    parser.add_argument("--src", help="Chromium src dir to update")
    parser.add_argument("--preview", help="directory to write preview PNGs to")
    parser.add_argument("--validate", action="store_true",
                        help="only check that the SVG renders")
    args = parser.parse_args()

    for tool in ("rsvg-convert", MAGICK):
        if not shutil.which(tool):
            sys.exit(f"error: '{tool}' not found (install librsvg and imagemagick)")
    try:
        validate(args.svg)
    except subprocess.CalledProcessError:
        sys.exit(f"error: {args.svg} is not a renderable SVG")
    if args.validate:
        return
    if args.preview:
        preview(args.svg, args.preview, args.name)
    if args.src and not replace_all(args.svg, args.src, args.name):
        sys.exit(1)


if __name__ == "__main__":
    main()
