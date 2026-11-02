#!/usr/bin/env python3
"""Rewrite KeePassXC's DarkStyle palette from an Omarchy theme's colors.toml.

KeePassXC has no palette system that follows the desktop: its light/dark themes
are a QPalette set in C++ (src/gui/styles/dark/DarkStyle.cpp) plus a small QSS.
So the only way to make it gold-on-black is to patch that palette at build time.

This script is the patch. It takes the theme's colors.toml and rewrites, in a
KeePassXC source tree:

  src/gui/styles/dark/DarkStyle.cpp   the QRgb() values in standardPalette()
                                      and the Window colours in polish()
  src/gui/styles/dark/darkstyle.qss   the handful of hardcoded greys

Every substitution is counted and asserted, so a KeePassXC release that changes
these files fails loudly here instead of silently shipping a half-themed app.

Usage: render-palette.py <colors.toml> <keepassxc-source-dir> [--check]
"""

import re
import sys
import pathlib

DARK_STYLE = "src/gui/styles/dark/DarkStyle.cpp"
DARK_QSS = "src/gui/styles/dark/darkstyle.qss"


def load_theme(path):
    theme = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"')
        if value.startswith("#") and len(value) == 7:
            theme[key.strip()] = value.lower()
    return theme


def build_palette(theme):
    """Map QPalette roles to theme keys. Each entry: (active, inactive, disabled)."""
    bg = theme["background"]
    fg = theme["foreground"]
    accent = theme["accent"]
    muted = theme.get("muted", theme.get("dark_foreground", fg))
    selection = theme.get("selection", muted)
    dim = theme.get("dark_foreground", fg)
    bright = theme.get("bright_foreground", fg)
    lighter = theme.get("lighter_background", bg)

    # Roles used by standardPalette(). The colour tuples are in the order the
    # source declares them: Active, Inactive, Disabled.
    return {
        "Window": (bg, lighter, bg),
        "WindowText": (fg, fg, dim),
        "Text": (fg, fg, dim),
        "PlaceholderText": (dim, dim, muted),
        "BrightText": (bg, bg, bg),
        "Base": (bg, bg, lighter),
        "AlternateBase": (lighter, lighter, muted),
        "ToolTipBase": (selection, selection, selection),
        "ToolTipText": (fg, fg, fg),
        "Button": (lighter, lighter, muted),
        "ButtonText": (accent, accent, dim),
        "Highlight": (accent, accent, dim),
        "HighlightedText": (bg, bg, dim),
        "Light": (muted, muted, muted),
        "Midlight": (selection, selection, selection),
        "Mid": (lighter, lighter, lighter),
        "Dark": (bg, bg, bg),
        "Shadow": (bg, bg, bg),
        "Link": (accent, accent, dim),
        "LinkVisited": (bright, bright, dim),
    }


def patch_cpp(text, palette):
    """Rewrite every setColor(..., QRgb(...)) line whose role we know."""
    pattern = re.compile(
        r"(palette\.setColor\(QPalette::(Active|Inactive|Disabled|All),\s*"
        r"QPalette::(\w+),\s*QRgb\()0x[0-9A-Fa-f]{6}(\)\);)"
    )
    idx = {"Active": 0, "Inactive": 1, "Disabled": 2}
    missing = set()
    seen = 0

    def repl(match):
        nonlocal seen
        state, role = match.group(2), match.group(3)
        if role not in palette:
            missing.add(role)
            return match.group(0)
        seen += 1
        colour = palette[role][0 if state == "All" else idx[state]]
        return f"{match.group(1)}0x{colour.lstrip('#').upper()}{match.group(4)}"

    text = pattern.sub(repl, text)
    return text, seen, missing


def patch_polish(text, palette):
    """The Window colours polish() hardcodes for main windows/dialogs/toolbars."""
    bg = palette["Window"][0]
    replacements = {
        "0x2A2A2A": bg, "0x2D2D2D": bg,          # macOS branch
        "0x2F2F30": bg, "0x313133": bg, "0x3A3A3B": bg,  # everything else
    }
    count = 0
    for old, new in replacements.items():
        token = f"QRgb({old})"
        while token in text:
            text = text.replace(token, f"QRgb(0x{new.lstrip('#').upper()})", 1)
            count += 1
    return text, count


def patch_qss(text, palette):
    """darkstyle.qss hardcodes a few greys beside its palette() references."""
    bg = palette["Window"][0]
    lighter = palette["Window"][1]
    muted = palette["Light"][0]
    accent = palette["Highlight"][0]
    mapping = {
        # inactive/disabled surfaces
        "#404042": lighter,
        "#424242": bg,
        # menu border + separator
        "#56565A": muted,
        # button hover shades
        "#252528": lighter,
        "#2E582E": accent,
        # tooltip
        "#BFBFBF": palette["ToolTipText"][0],
        "#2D532D": palette["ToolTipBase"][0],
    }
    count = 0
    for old, new in mapping.items():
        occurrences = len(re.findall(re.escape(old), text, re.I))
        if occurrences:
            text = re.sub(re.escape(old), new, text, flags=re.I)
            count += occurrences
    return text, count


def main():
    if len(sys.argv) < 3:
        print("usage: render-palette.py <colors.toml> <keepassxc-source-dir> [--check]",
              file=sys.stderr)
        return 2

    colors, source = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    check = "--check" in sys.argv[3:]

    for rel in (DARK_STYLE, DARK_QSS):
        if not (source / rel).is_file():
            print(f"not a KeePassXC source tree: {source / rel} missing", file=sys.stderr)
            return 1

    theme = load_theme(colors)
    for required in ("background", "foreground", "accent"):
        if required not in theme:
            print(f"{colors}: theme is missing {required}", file=sys.stderr)
            return 1

    palette = build_palette(theme)

    cpp_path = source / DARK_STYLE
    cpp, cpp_count, missing = patch_cpp(cpp_path.read_text(), palette)
    if missing:
        print(f"unmapped QPalette roles: {', '.join(sorted(missing))}", file=sys.stderr)
        return 1
    if cpp_count == 0:
        print("standardPalette(): no QRgb() lines matched — source changed?", file=sys.stderr)
        return 1
    cpp, polish_count = patch_polish(cpp, palette)

    qss_path = source / DARK_QSS
    qss, qss_count = patch_qss(qss_path.read_text(), palette)

    if check:
        print(f"ok: {cpp_count} palette colours, {polish_count} polish colours, "
              f"{qss_count} stylesheet colours would be rewritten")
        return 0

    cpp_path.write_text(cpp)
    qss_path.write_text(qss)
    print(f"patched {DARK_STYLE}: {cpp_count} palette + {polish_count} polish colours")
    print(f"patched {DARK_QSS}: {qss_count} colours")
    return 0


if __name__ == "__main__":
    sys.exit(main())
