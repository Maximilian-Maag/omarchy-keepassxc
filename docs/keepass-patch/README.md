# KeePassXC palette patch

Makes KeePassXC's dark theme use the Omarchy theme's colours (gold on black)
instead of its own grey.

## Why this is a patch and not a setting

KeePassXC has no palette system that follows the desktop. Its themes are
`auto`, `light`, `dark` and `classic`; the colours are a `QPalette` set in C++
(`src/gui/styles/dark/DarkStyle.cpp`) plus a small embedded QSS. Measured on
2.7.12:

| `ApplicationTheme` | result |
| --- | --- |
| `auto` | **light/white** — it does not read the GTK palette, even with `QT_QPA_PLATFORMTHEME=gtk3` |
| `dark` | dark **grey** — KeePassXC's own palette |
| `light` / `classic` | light |

An app's own `setStyleSheet()`/palette always wins over a platform theme, so
qt6ct/Kvantum cannot override it either, and `strings` on the binary shows no
hook for an external stylesheet or theme directory. The only way to change the
colours is to change the C++ palette and rebuild.

## What the patch does

`render-palette.py` rewrites, in a KeePassXC source tree:

- `src/gui/styles/dark/DarkStyle.cpp` — every `QRgb()` in `standardPalette()`
  and the `Window` colours in `polish()`
- `src/gui/styles/dark/darkstyle.qss` — the handful of hardcoded greys

Colours come from the theme's `colors.toml` (`background`, `foreground`,
`accent`, `muted`, `selection`, `dark_foreground`, `bright_foreground`,
`lighter_background`). Nothing is hardcoded in the
script, so any theme works.

Every substitution is counted and asserted: a KeePassXC release that changes
these files makes the script fail loudly rather than ship a half-themed app.

## Build

```bash
docs/keepass-patch/build-patched-keepassxc.sh            # current Omarchy theme
docs/keepass-patch/build-patched-keepassxc.sh "Catppuccin"  # a named theme
```

It fetches the Arch packaging for the current KeePassXC, verifies the patcher
still recognises the source, builds a package with `makepkg`, and prints the
`sudo pacman -U ...` line. Build dependencies (as of 2.8.0):

```bash
sudo pacman -S --needed asciidoctor cmake git qt6-tools
```

The build tree is kept at `~/.cache/omarchy-keepassxc-build` (override with
`KPXC_BUILD_DIR`).

## Install

```bash
sudo pacman -U ~/.cache/omarchy-keepassxc-build/pkg/keepassxc-*.pkg.tar.zst
```

Then set the theme in KeePassXC to **Dark** (the patched palette is the dark
one). The plugin's theme hook already writes `ApplicationTheme=dark` for dark
Omarchy themes.

## Durability

A stock `keepassxc` upgrade replaces the patched package. Re-run the build
script afterwards. This is the same trade-off as the patched QtWebEngine in
`omarchy-qutebrowser` (`docs/engine-patch/`).

## Tests

`tests/test_unit_keepass_palette.py` runs the generator against a fixture source
tree and asserts the mapping, idempotency, and that it refuses to run on a
source it does not recognise.
