#!/usr/bin/env python3
"""Set KeePassXC's UI theme in keepassxc.ini without disturbing other keys.

KeePassXC's own theme engine does not follow the GTK/Omarchy palette, and its
"auto" mode renders the unlock window light before its palette is applied.
Writing an explicit [GUI] ApplicationTheme makes it match the desktop.

Values accepted by KeePassXC: auto, light, dark, classic.

The file is edited line-by-line on purpose: KeePassXC's config holds a KeeShare
XML blob whose escaping configparser would mangle.
"""
import os
import re
import sys

VALID = ("auto", "light", "dark", "classic")


def main() -> int:
    theme = sys.argv[1] if len(sys.argv) > 1 else ""
    if theme not in VALID:
        print(f"usage: {sys.argv[0]} <{'|'.join(VALID)}>", file=sys.stderr)
        return 2

    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    ini = os.path.join(config_home, "keepassxc", "keepassxc.ini")
    os.makedirs(os.path.dirname(ini), exist_ok=True)

    try:
        with open(ini, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        lines = []

    out, in_gui, set_key = [], False, False
    for line in lines:
        stripped = line.strip()
        is_header = stripped.startswith("[") and stripped.endswith("]")
        # Leaving [GUI] without having set the key: insert it before the new header.
        if is_header and in_gui and not set_key:
            out.append(f"ApplicationTheme={theme}")
            set_key = True
        if is_header:
            in_gui = stripped == "[GUI]"
        if in_gui and re.match(r"\s*ApplicationTheme\s*=", line):
            out.append(f"ApplicationTheme={theme}")
            set_key = True
            continue
        out.append(line)

    if in_gui and not set_key:
        out.append(f"ApplicationTheme={theme}")
        set_key = True
    if not any(l.strip() == "[GUI]" for l in out):
        out.append("[GUI]")
        out.append(f"ApplicationTheme={theme}")

    with open(ini, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")

    print(f"keepassxc: ApplicationTheme={theme} ({ini})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
