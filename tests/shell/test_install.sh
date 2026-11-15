#!/bin/bash
# Shell tests for install.sh — plain bash, no bats.
#
# install.sh is run against a fake HOME/XDG_CONFIG_HOME with stub omarchy/pacman/
# sudo/pkill/sleep/pip binaries, so no package is ever touched on the real system.
# The focus is issue #3: the script must NOT print a success line after an action
# it wraps in `|| true` when that action actually failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/install.sh"
REAL_PY="$(command -v python3)"
ORIG_PATH="$PATH"

FAIL=0
pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

assert_contains() { # file needle description
  if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3 (missing '$2' in $1)"; fi
}
assert_not_contains() { # file needle description
  if grep -qF -- "$2" "$1" 2>/dev/null; then fail "$3 (unexpected '$2' in $1)"; else pass "$3"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_FAKE="$TMP/home"
CONFIG="$TMP/config"
BIN="$TMP/bin"
LOG="$TMP/stub.log"
OUT="$TMP/out.log"
mkdir -p "$HOME_FAKE" "$CONFIG/omarchy/themes" "$BIN"

write_stub() { # name body
  printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"
  chmod 755 "$BIN/$1"
}

# pacman: -Qi answers "is it installed?"; -Rs/-R answer the removal result.
write_stub pacman '
echo "pacman $*" >> "$STUB_LOG"
case "$1" in
  -Qi)
    case "$2" in
      keepass) exit "${STUB_KEEPASS_INSTALLED:-1}" ;;
      mono)    exit "${STUB_MONO_INSTALLED:-1}" ;;
    esac
    exit 1 ;;
  -Rs|-R|-Rns) exit "${STUB_REMOVE_RC:-0}" ;;
  -Qdtq)       exit "${STUB_ORPHANS_RC:-1}" ;;
esac
exit 0'

# sudo just logs and delegates, so the pacman stub above still answers.
write_stub sudo 'echo "sudo $*" >> "$STUB_LOG"; exec "$@"'

# omarchy: pkg add (per-package rc), theme current (STUB_THEME), hook install.
write_stub omarchy '
echo "omarchy $*" >> "$STUB_LOG"
case "$1 $2" in
  "pkg add")
    case "$3" in
      keepassxc)     exit "${STUB_PKG_KEEPASSXC_RC:-0}" ;;
      python-pynacl) exit "${STUB_PKG_PYNACL_RC:-0}" ;;
    esac
    exit 0 ;;
  "theme current") printf "%s\n" "${STUB_THEME:-}"; exit 0 ;;
  "hook install")  exit 0 ;;
esac
exit 0'

write_stub pip 'echo "pip $*" >> "$STUB_LOG"; exit "${STUB_PIP_RC:-0}"'
write_stub pkill 'echo "pkill $*" >> "$STUB_LOG"; exit 0'
write_stub sleep 'echo "sleep $*" >> "$STUB_LOG"; exit 0'
# python3 passthrough so install.sh's bare `python3` (the theme hook) works.
printf '#!/bin/bash\necho "python3 $*" >> "$STUB_LOG"\nexec "%s" "$@"\n' "$REAL_PY" > "$BIN/python3"
chmod 755 "$BIN/python3"

reset() {
  rm -rf "$CONFIG/omarchy/themes" "$CONFIG/keepassxc"
  mkdir -p "$CONFIG/omarchy/themes"
  : > "$LOG"
  : > "$OUT"
}

mktheme() { # name mode
  mkdir -p "$CONFIG/omarchy/themes/$1"
  printf 'mode = "%s"\nbackground = "#101010"\n' "$2" > "$CONFIG/omarchy/themes/$1/colors.toml"
}

# run_install ENV=VAL...   — runs install.sh with the fake env, stdout+stderr in $OUT
run_install() {
  env HOME="$HOME_FAKE" XDG_CONFIG_HOME="$CONFIG" PATH="$BIN:$ORIG_PATH" STUB_LOG="$LOG" \
    HYPRLAND_INSTANCE_SIGNATURE= "$@" bash "$INSTALL" >"$OUT" 2>&1
}

# ── a failed KeePass2 removal must not print success ───────────────────────
reset
run_install STUB_KEEPASS_INSTALLED=0 STUB_REMOVE_RC=1 STUB_PKG_KEEPASSXC_RC=0 STUB_THEME=
rc=$?
if (( rc == 0 )); then pass "a failed removal does not abort the script"; else fail "a failed removal must not abort the script (got $rc)"; fi
assert_not_contains "$OUT" "KeePass2 removed." "a failed removal does not report success"
assert_contains "$OUT" "could not remove KeePass2" "a failed removal is explained"
assert_contains "$OUT" "Done!" "the script still reaches the end"

# ── a successful removal does report it ────────────────────────────────────
reset
run_install STUB_KEEPASS_INSTALLED=0 STUB_REMOVE_RC=0 STUB_PKG_KEEPASSXC_RC=0 STUB_THEME=
assert_contains "$OUT" "KeePass2 removed." "a successful removal reports success"

# ── a failed KeePassXC install must not print success (and must not abort) ──
reset
run_install STUB_KEEPASS_INSTALLED=1 STUB_REMOVE_RC=0 STUB_PKG_KEEPASSXC_RC=1 STUB_THEME=
rc=$?
if (( rc == 0 )); then pass "a failed install does not abort the script"; else fail "a failed install must not abort the script (got $rc)"; fi
assert_not_contains "$OUT" "KeePassXC installed." "a failed install does not report success"
assert_contains "$OUT" "could not install KeePassXC" "a failed install is explained"
assert_contains "$OUT" "Done!" "the script still reaches the end after a failed install"

# ── an unlocatable theme: the hook is a silent no-op, so no success line ────
reset
run_install STUB_KEEPASS_INSTALLED=0 STUB_REMOVE_RC=0 STUB_PKG_KEEPASSXC_RC=0 STUB_THEME=ghost
assert_not_contains "$OUT" "Set KeePassXC theme to match" "an unknown theme is not reported as set"
assert_contains "$OUT" "has no colors.toml" "an unknown theme is reported accurately"

# ── a locatable theme is applied and reported ──────────────────────────────
reset; mktheme nord dark
run_install STUB_KEEPASS_INSTALLED=0 STUB_REMOVE_RC=0 STUB_PKG_KEEPASSXC_RC=0 STUB_THEME=nord
assert_contains "$OUT" "Set KeePassXC theme to match: nord" "a real theme reports success"
assert_contains "$CONFIG/keepassxc/keepassxc.ini" "ApplicationTheme=dark" "a real theme is applied to keepassxc.ini"

exit "$FAIL"
