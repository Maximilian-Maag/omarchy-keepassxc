#!/bin/bash
# Shell tests for hooks/theme-set — plain bash, no bats.
#
# The hook is run against a fake HOME/XDG_CONFIG_HOME and stub pgrep/pkill/
# setsid/uwsm-app/sleep/python3 binaries, so the real session is never touched.
# Assertions are on observable effects: keepassxc.ini and the stub call log.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/theme-set"
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
assert_file() {
  if [ -f "$1" ]; then pass "$2"; else fail "$2 (no such file: $1)"; fi
}
assert_no_file() {
  if [ -f "$1" ]; then fail "$2 (unexpected file: $1)"; else pass "$2"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_FAKE="$TMP/home"
CONFIG="$TMP/config"
BIN="$TMP/bin"
LOG="$TMP/stub.log"
mkdir -p "$HOME_FAKE" "$CONFIG/omarchy/themes" "$BIN"

write_stub() { # name body
  printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"
  chmod 755 "$BIN/$1"
}
write_stub pgrep 'echo "pgrep $*" >> "$STUB_LOG"; exit "${STUB_PGREP_RC:-1}"'
write_stub pkill 'echo "pkill $*" >> "$STUB_LOG"; exit "${STUB_PKILL_RC:-0}"'
write_stub setsid 'echo "setsid $*" >> "$STUB_LOG"; exit 0'
write_stub uwsm-app 'echo "uwsm-app $*" >> "$STUB_LOG"; exit 0'
write_stub sleep 'echo "sleep $*" >> "$STUB_LOG"; exit 0'
# python3 passthrough that records invocation, so no-op paths can be proven silent
printf '#!/bin/bash\necho "python3 $*" >> "$STUB_LOG"\nexec "%s" "$@"\n' "$REAL_PY" > "$BIN/python3"
chmod 755 "$BIN/python3"

INI="$CONFIG/keepassxc/keepassxc.ini"

mktheme() { # name mode
  mkdir -p "$CONFIG/omarchy/themes/$1"
  printf 'mode = "%s"\nbackground = "#101010"\n' "$2" > "$CONFIG/omarchy/themes/$1/colors.toml"
}

run_hook() { # theme [pgrep_rc]
  local theme="${1:-}" prc="${2:-1}"
  HOME="$HOME_FAKE" XDG_CONFIG_HOME="$CONFIG" PATH="$BIN:$ORIG_PATH" \
    STUB_LOG="$LOG" STUB_PGREP_RC="$prc" bash "$HOOK" $theme
}

reset() {
  rm -rf "$CONFIG/omarchy/themes" "$CONFIG/keepassxc"
  mkdir -p "$CONFIG/omarchy/themes"
  : > "$LOG"
}

# ── mode mapping ──────────────────────────────────────────────────────────
reset; mktheme nord dark
run_hook nord
assert_file "$INI" "a dark theme writes keepassxc.ini"
assert_contains "$INI" "[GUI]" "the [GUI] section is present"
assert_contains "$INI" "ApplicationTheme=dark" "dark mode writes ApplicationTheme=dark"

reset; mktheme nord light
run_hook nord
assert_contains "$INI" "ApplicationTheme=light" "light mode writes ApplicationTheme=light"

reset; mktheme nord dark
run_hook Nord
assert_contains "$INI" "ApplicationTheme=dark" "a Title Case theme name is normalised"

# ── existing content is preserved ─────────────────────────────────────────
reset; mktheme nord dark
mkdir -p "$CONFIG/keepassxc"
printf 'LastDir=/data\n\n[GUI]\nFoo=bar\n' > "$INI"
run_hook nord
assert_contains "$INI" "LastDir=/data" "unrelated keys survive"
assert_contains "$INI" "Foo=bar" "an existing [GUI] key survives"
assert_contains "$INI" "ApplicationTheme=dark" "the theme is still applied"

# ── no-op paths ───────────────────────────────────────────────────────────
reset; mktheme nord dark
run_hook does-not-exist; rc=$?
if (( rc == 0 )); then pass "a missing theme exits 0"; else fail "a missing theme must exit 0 (got $rc)"; fi
assert_no_file "$INI" "a missing theme leaves keepassxc.ini alone"
assert_not_contains "$LOG" "python3 " "a missing theme never invokes the editor"

reset; mktheme nord dark
run_hook ""; rc=$?
if (( rc == 0 )); then pass "an empty theme name exits 0"; else fail "an empty theme name must exit 0 (got $rc)"; fi
assert_no_file "$INI" "an empty theme name is a no-op"
assert_not_contains "$LOG" "python3 " "an empty theme name never invokes the editor"

# ── restart policy ────────────────────────────────────────────────────────
reset; mktheme nord light
mkdir -p "$CONFIG/keepassxc"
printf '[GUI]\nApplicationTheme=dark\n' > "$INI"
run_hook nord 0
assert_contains "$LOG" "pkill" "a changed mode restarts a running KeePassXC"

reset; mktheme nord dark
mkdir -p "$CONFIG/keepassxc"
printf '[GUI]\nApplicationTheme=dark\n' > "$INI"
run_hook nord 0
assert_not_contains "$LOG" "pkill" "an unchanged mode never restarts KeePassXC"

exit "$FAIL"