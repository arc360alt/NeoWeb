#!/usr/bin/env python3
"""Applies NeoWeb's generated customizations to a pristine Chromium checkout.

Everything here is driven by neoweb.conf and the files in branding/, and is
written as small search-and-replace steps rather than diff patches so it keeps
working when Chromium moves code around. Anything that can't be found is
reported instead of silently skipped.

Steps:
  1. branding    chrome/app/theme/chromium/BRANDING (product/company names)
  2. strings     product name in UI text, including all translations
  3. source      profile dir, desktop/icon names, default theme color
  4. icons       every Chromium logo, regenerated from branding/icon.svg
"""

import argparse
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import icons  # noqa: E402

warnings = []


def warn(msg):
    warnings.append(msg)
    print(f"    WARNING: {msg}", file=sys.stderr)


def read_conf(path):
    conf = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'\s*([A-Z_][A-Z0-9_]*)=(.*)$', line)
            if not m:
                continue
            value = m.group(2).strip()
            if value[:1] in ('"', "'"):
                value = value[1:value.index(value[0], 1)]
            else:
                value = value.split("#", 1)[0].strip()
            conf[m.group(1)] = value
    return conf


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


# ------------------------------------------------------------------ branding

def apply_branding(src, conf):
    path = os.path.join(src, "chrome/app/theme/chromium/BRANDING")
    if not os.path.exists(path):
        warn("BRANDING file not found")
        return
    values = {
        "COMPANY_FULLNAME": conf["COMPANY_NAME"],
        "COMPANY_SHORTNAME": conf["COMPANY_NAME"],
        "PRODUCT_FULLNAME": conf["BROWSER_NAME"],
        "PRODUCT_SHORTNAME": conf["BROWSER_NAME"],
        "PRODUCT_INSTALLER_FULLNAME": conf["BROWSER_NAME"] + " Installer",
        "PRODUCT_INSTALLER_SHORTNAME": conf["BROWSER_NAME"] + " Installer",
        "COPYRIGHT": conf["COPYRIGHT"],
        "MAC_BUNDLE_ID": conf["MAC_BUNDLE_ID"],
    }
    lines = []
    for line in read_text(path).splitlines():
        key = line.split("=", 1)[0]
        lines.append(f"{key}={values.pop(key)}" if key in values else line)
    write_text(path, "\n".join(lines) + "\n")
    print("    branding: BRANDING updated")


# ------------------------------------------------------------------- strings

def load_string_rules(path, conf):
    """Parses branding/strings.conf into (files, [(regex, replacement)])."""
    files, rules = [], []
    for raw in read_text(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        line = re.sub(r"\{([A-Z_][A-Z0-9_]*)\}",
                      lambda m: conf.get(m.group(1), m.group(0)), line)
        if line.startswith("file:"):
            files.append(line[5:].strip())
            continue
        if "=>" not in line:
            warn(f"strings.conf: ignoring line without '=>': {raw}")
            continue
        find, repl = (part.strip() for part in line.split("=>", 1))
        if find.startswith("re:"):
            rules.append((re.compile(find[3:]), repl))
        else:
            rules.append((re.compile(re.escape(find)), repl.replace("\\", "\\\\")))
    return files, rules


# Tags and comments are left alone; only the text between them is rewritten,
# so ids, attributes and placeholders are never touched.
MARKUP = re.compile(r"(<!--.*?-->|<[^>]*>)", re.S)


def replace_in_text(xml, rules):
    parts = MARKUP.split(xml)
    for i in range(0, len(parts), 2):
        for regex, repl in rules:
            parts[i] = regex.sub(repl, parts[i])
    return "".join(parts)


def grd_sources(grd):
    """The grd plus every <part> file it includes, recursively."""
    out, todo = [], [grd]
    while todo:
        path = todo.pop()
        out.append(path)
        for part in re.findall(r'<part\s+file="([^"]+)"', read_text(path)):
            todo.append(os.path.normpath(os.path.join(os.path.dirname(path), part)))
    return out


def grd_translations(grd):
    base = os.path.dirname(grd)
    found = []
    for path in grd_sources(grd):
        block = re.search(r"<translations>(.*?)</translations>", read_text(path), re.S)
        if block:
            for rel in re.findall(r'<file\s+path="([^"]+\.xtb)"', block.group(1)):
                found.append(os.path.normpath(os.path.join(base, rel)))
    return found


def message_ids(src, grd):
    """Translation ids of every <message> in the grd, in document order.

    Ids are hashes of the English text, so changing that text orphans every
    translation. Computing ids before and after the edit (with Chromium's own
    grit) lets us re-key the .xtb files instead.
    """
    grit_dir = os.path.join(src, "tools/grit")
    if grit_dir not in sys.path:
        sys.path.insert(0, grit_dir)
    from grit import grd_reader
    from grit.node import message

    try:
        root = grd_reader.Parse(grd, skip_validation_checks=True)
    except TypeError:
        root = grd_reader.Parse(grd)
    ids = []
    for node in root.Preorder():
        if isinstance(node, message.MessageNode):
            ids.append(node.GetCliques()[0].GetId())
    return ids


def apply_strings(src, conf):
    files, rules = load_string_rules(os.path.join(ROOT, "branding/strings.conf"), conf)
    if not rules:
        print("    strings: no rules in branding/strings.conf")
        return
    for rel in files:
        grd = os.path.join(src, rel)
        if not os.path.exists(grd):
            warn(f"strings: {rel} not found")
            continue
        try:
            before = message_ids(src, grd)
        except Exception as e:  # grit API changed; still rename, but warn.
            warn(f"strings: could not parse {rel} with grit ({e}); "
                 "translations for renamed strings may fall back to English")
            before = None

        changed = 0
        for path in grd_sources(grd):
            old = read_text(path)
            new = replace_in_text(old, rules)
            if new != old:
                write_text(path, new)
                changed += 1

        remap = {}
        if before is not None:
            after = message_ids(src, grd)
            if len(after) == len(before):
                remap = {o: n for o, n in zip(before, after) if o != n}
            else:
                warn(f"strings: message count changed while editing {rel}")

        id_attr = re.compile(r'(<translation\s+id=")(\d+)(")')
        xtbs = grd_translations(grd)
        for xtb in xtbs:
            if not os.path.exists(xtb):
                continue
            text = replace_in_text(read_text(xtb), rules)
            text = id_attr.sub(lambda m: m.group(1) + remap.get(m.group(2), m.group(2)) + m.group(3), text)
            write_text(xtb, text)
        print(f"    strings: {rel}: {len(remap)} messages renamed, "
              f"{len(xtbs)} translation files updated")


# -------------------------------------------------------------------- source

VARIANTS = {
    "system": "kSystem",
    "tonal_spot": "kTonalSpot",
    "neutral": "kNeutral",
    "vibrant": "kVibrant",
    "expressive": "kExpressive",
}


def source_edits(conf):
    """(file, regex, replacement, description). Each must match exactly once."""
    bid = conf["BROWSER_ID"]
    edits = [
        ("chrome/common/chrome_paths_linux.cc",
         r'(std::string data_dir_basename = )"chromium";',
         rf'\1"{bid}";',
         f"profile folder is ~/.config/{bid}"),
        ("chrome/common/channel_info_posix.cc",
         r'return "chromium-browser\.desktop";',
         f'return "{bid}.desktop";',
         f"desktop file / window class is {bid}"),
        ("chrome/browser/shell_integration_linux.cc",
         r'return "chromium-browser";',
         f'return "{bid}";',
         f"icon name is {bid}"),
    ]

    color = conf.get("THEME_COLOR", "").lstrip("#")
    if color:
        if not re.fullmatch(r"[0-9a-fA-F]{6}", color):
            sys.exit(f"error: THEME_COLOR must look like #00E8DA, got {conf['THEME_COLOR']}")
        r, g, b = color[0:2], color[2:4], color[4:6]
        edits.append((
            "chrome/browser/themes/theme_service.cc",
            r"(RegisterIntegerPref\(\s*prefs::kUserColor,)\s*SK_ColorTRANSPARENT",
            rf"\1\n      static_cast<int>(SkColorSetRGB(0x{r}, 0x{g}, 0x{b}))",
            f"default theme color #{color.upper()}"))

    variant = conf.get("THEME_VARIANT", "system")
    if variant not in VARIANTS:
        sys.exit(f"error: THEME_VARIANT must be one of {', '.join(VARIANTS)}")
    if variant != "system":
        edits.append((
            "chrome/browser/themes/theme_service.cc",
            r"(prefs::kBrowserColorVariant,\s*static_cast<int>\(ui::mojom::BrowserColorVariant::)kSystem\)",
            rf"\1{VARIANTS[variant]})",
            f"default theme variant {variant}"))

    if conf.get("DEFAULT_TO_CLASSIC_THEME") == "1":
        edits.append((
            "chrome/browser/themes/theme_service.cc",
            r"(RegisterIntegerPref\(\s*prefs::kSystemTheme,\s*)static_cast<int>\(ui::GetDefaultSystemTheme\(\)\)",
            r"\1static_cast<int>(ui::SystemTheme::kDefault)",
            "new profiles use the NeoWeb theme instead of GTK"))
    return edits


def apply_source_edits(src, conf):
    for rel, pattern, repl, what in source_edits(conf):
        path = os.path.join(src, rel)
        if not os.path.exists(path):
            warn(f"source: {rel} not found ({what})")
            continue
        text, count = re.subn(pattern, repl, read_text(path))
        if count != 1:
            warn(f"source: expected 1 match in {rel}, found {count} ({what}); "
                 "Chromium changed this code, add a patch in patches/ instead")
            continue
        write_text(path, text)
        print(f"    source: {what}")


# ---------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--src", required=True, help="Chromium src directory")
    parser.add_argument("--only", choices=["branding", "strings", "source", "icons"])
    parser.add_argument("--strict", action="store_true", help="exit 2 on any warning")
    args = parser.parse_args()

    conf = read_conf(os.path.join(ROOT, "neoweb.conf"))
    steps = {
        "branding": lambda: apply_branding(args.src, conf),
        "strings": lambda: apply_strings(args.src, conf),
        "source": lambda: apply_source_edits(args.src, conf),
        "icons": lambda: icons.replace_all(os.path.join(ROOT, "branding/icon.svg"),
                                           args.src, conf["BROWSER_NAME"])
                         or warn("icons: some icons could not be regenerated"),
    }
    for name, step in steps.items():
        if args.only in (None, name):
            step()

    if warnings:
        print(f"    {len(warnings)} warning(s); see above.", file=sys.stderr)
        if args.strict:
            sys.exit(2)


if __name__ == "__main__":
    main()
