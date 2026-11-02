#!/bin/bash
# Build a KeePassXC whose dark theme uses the Omarchy palette.
#
# KeePassXC cannot follow the desktop palette (see render-palette.py); this builds
# a patched package with the current theme baked in. Run it, then install the
# package it prints with `sudo pacman -U <file>`.
#
# Usage: build-patched-keepassxc.sh [theme-name]
#   theme-name  Omarchy theme to take the palette from (default: the current theme)
#
# Like docs/engine-patch/ in omarchy-qutebrowser, this has to be re-run after a
# stock keepassxc upgrade, which replaces the patched package.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
THEME_NAME=${1:-$(omarchy theme current 2>/dev/null)}

die() { echo "build-patched-keepassxc: $*" >&2; exit 1; }

[[ -n $THEME_NAME ]] || die "no theme given and 'omarchy theme current' is empty"

SLUG=$(printf '%s' "$THEME_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
COLORS=""
for base in "$HOME/.config/omarchy/themes" /usr/share/omarchy/themes; do
  [[ -f $base/$SLUG/colors.toml ]] && { COLORS=$base/$SLUG/colors.toml; break; }
done
[[ -n $COLORS ]] || die "no colors.toml for theme '$THEME_NAME' (looked in $HOME/.config/omarchy/themes and /usr/share/omarchy/themes)"

command -v makepkg >/dev/null || die "makepkg not found (install base-devel)"
command -v python3 >/dev/null || die "python3 not found"

WORK=${KPXC_BUILD_DIR:-$HOME/.cache/omarchy-keepassxc-build}
rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> packaging repo"
git clone -q --depth 1 https://gitlab.archlinux.org/archlinux/packaging/packages/keepassxc "$WORK/pkg"
cd "$WORK/pkg"
PKGVER=$(sed -nE 's/^pkgver=(.*)/\1/p' PKGBUILD | head -1)
echo "==> KeePassXC $PKGVER, palette from $THEME_NAME ($COLORS)"

cp "$HERE/render-palette.py" .
cp "$COLORS" theme-colors.toml

# Fail before a 20-minute build if the source no longer matches the patcher.
echo "==> verifying the patch applies"
SRC="$WORK/src-check"
git clone -q --depth 1 --branch "$PKGVER" https://github.com/keepassxreboot/keepassxc.git "$SRC" 2>/dev/null \
  || die "cannot fetch keepassxc $PKGVER source"
python3 render-palette.py theme-colors.toml "$SRC" --check \
  || die "render-palette.py does not recognise this KeePassXC source; update it before building"

# Wire the patcher into the official PKGBUILD: ship both files as sources and run
# the patcher in prepare(). 'SKIP' is correct for local files makepkg does not fetch.
cat >> PKGBUILD <<'EOF'

# --- Omarchy palette patch ---
source+=('render-palette.py' 'theme-colors.toml')
sha256sums+=('SKIP' 'SKIP')

prepare() {
	cd "${pkgname}"
	python3 ../render-palette.py ../theme-colors.toml .
}
EOF

echo "==> building (this takes a while)"
# The packaging repo ships the release signing keys in keys/pgp/, but makepkg only
# finds them if the user's gnupg home already has them. Seed them so the source
# signature is still verified rather than skipped.
if compgen -G "keys/pgp/*.asc" >/dev/null; then
  gpg --import keys/pgp/*.asc >/dev/null 2>&1 || true
fi

# --nocheck: upstream's check() runs the GUI test suite under xvfb, which we do
# not need to prove the palette patch works.
makepkg -f --nocheck --noconfirm

PKG=$(ls -t keepassxc-"${PKGVER}"-*.pkg.tar.zst 2>/dev/null | head -1)
[[ -n $PKG ]] || die "build finished but no package was produced"

cat <<MSG

Built: $WORK/pkg/$PKG

Install it yourself (root):

    sudo pacman -U "$WORK/pkg/$PKG"

The build tree is kept at $WORK so you can reinstall or rebuild without
recompiling; delete it when you no longer need it.
MSG
