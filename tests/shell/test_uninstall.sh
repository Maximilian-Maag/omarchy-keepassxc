#!/bin/bash
# The `--uninstall` contract, in a throwaway HOME/XDG with the desktop's commands
# stubbed — no package and no real session is ever touched.
#
# What is checked: a full install -> uninstall round-trip leaves the user's own
# config byte-identical (sha256) and leaves no marker/blank line behind, removes
# exactly the artifacts the install added, leaves a foreign file alone, and never
# reaches for a package.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
INSTALL="$REPO/install.sh"
REAL_PY="$(command -v python3)"
ORIG_PATH="$PATH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check()         { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
check_file()    { if [[ -f $1 ]]; then ok "$2"; else bad "$2 (no file: $1)"; fi; }
check_no_file() { if [[ -e $1 ]]; then bad "$2 (still there: $1)"; else ok "$2"; fi; }

HOME_FAKE="$TMP/home"; CONFIG="$TMP/config"; BIN="$TMP/bin"; LOG="$TMP/stub.log"
mkdir -p "$HOME_FAKE" "$CONFIG/hypr" "$CONFIG/omarchy/themes" "$BIN"

write_stub() { printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod 755 "$BIN/$1"; }

# pacman: nothing installed, so the KeePass2/mono removal is a clean no-op — and a
# removal must never be attempted from `--uninstall` at all.
write_stub pacman 'echo "pacman $*" >> "$STUB_LOG"; exit 1'
write_stub sudo 'echo "sudo $*" >> "$STUB_LOG"; exec "$@"'
write_stub pkill 'echo "pkill $*" >> "$STUB_LOG"; exit 0'
write_stub sleep 'exit 0'
write_stub pip 'exit 0'
# omarchy: pkg add is a no-op, theme current names a locatable theme, and hook
# install copies the hook into theme-set.d exactly as the real one does.
write_stub omarchy '
echo "omarchy $*" >> "$STUB_LOG"
case "$1 $2" in
  "pkg add") exit 0 ;;
  "theme current") printf "%s\n" "nord"; exit 0 ;;
  "hook install")
    mkdir -p "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d"
    cp "$4" "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/$(basename "$4")" 2>/dev/null || true
    exit 0 ;;
esac
exit 0'
# python3 passthrough so install.sh's bare `python3` (the theme hook) works.
printf '#!/bin/bash\nexec "%s" "$@"\n' "$REAL_PY" > "$BIN/python3"; chmod 755 "$BIN/python3"

# A theme the plugin can locate, so the install's theme step runs for real.
mkdir -p "$CONFIG/omarchy/themes/nord"
printf 'mode = "dark"\nbackground = "#101010"\n' > "$CONFIG/omarchy/themes/nord/colors.toml"

run() {  # run [args...] — install.sh against the fake env
  env HOME="$HOME_FAKE" XDG_CONFIG_HOME="$CONFIG" PATH="$BIN:$ORIG_PATH" STUB_LOG="$LOG" \
    HYPRLAND_INSTANCE_SIGNATURE= bash "$INSTALL" "$@"
}

REQ='require("hypr.keepassxc-bindings")'
LAUNCH='o.launch_on_start("keepassxc")'
KBMARK='-- omarchy-keepassxc keybindings'
AUTOMARK='-- omarchy-keepassxc: start KeePassXC at login'

seed_user_config() {
  printf -- '-- my own hyprland.lua\nhl.monitor({ output = "eDP-1" })\n' > "$CONFIG/hypr/hyprland.lua"
  printf -- '-- my own autostart.lua\no.launch_on_start("waybar")\n' > "$CONFIG/hypr/autostart.lua"
  rm -rf "$CONFIG/omarchy/hooks" "$CONFIG/keepassxc"
  rm -f "$CONFIG/hypr/keepassxc-bindings.lua"
}

printf 'uninstall round-trip\n'

# ── the round-trip: install, then uninstall, and the user's files come back ─────
seed_user_config
before_hypr="$(sha256sum "$CONFIG/hypr/hyprland.lua" | cut -d' ' -f1)"
before_auto="$(sha256sum "$CONFIG/hypr/autostart.lua" | cut -d' ' -f1)"

run >/dev/null 2>&1
check "installing succeeds" "0" "$?"
check_file "$CONFIG/hypr/keepassxc-bindings.lua" "install copies the bindings fragment"
check "install appends the require line once" "1" "$(grep -cF -- "$REQ" "$CONFIG/hypr/hyprland.lua")"
check "install adds the autostart entry" "1" "$(grep -cF -- "$LAUNCH" "$CONFIG/hypr/autostart.lua")"
check_file "$CONFIG/omarchy/hooks/theme-set.d/keepassxc-theme-set" "install installs the theme-set hook"

run --uninstall >"$TMP/out" 2>&1
check "uninstalling succeeds" "0" "$?"
check_no_file "$CONFIG/hypr/keepassxc-bindings.lua" "the bindings fragment is gone"
check "the require line is gone" "0" "$(grep -cF -- "$REQ" "$CONFIG/hypr/hyprland.lua")"
check "the autostart entry is gone" "0" "$(grep -cF -- "$LAUNCH" "$CONFIG/hypr/autostart.lua")"
check_no_file "$CONFIG/omarchy/hooks/theme-set.d/keepassxc-theme-set" "the theme-set hook is gone"
check "the user's hyprland.lua is byte-identical to before" "$before_hypr" \
  "$(sha256sum "$CONFIG/hypr/hyprland.lua" | cut -d' ' -f1)"
check "the user's autostart.lua is byte-identical to before" "$before_auto" \
  "$(sha256sum "$CONFIG/hypr/autostart.lua" | cut -d' ' -f1)"
check "no keybindings marker is left behind" "0" "$(grep -c -- "$KBMARK" "$CONFIG/hypr/hyprland.lua")"
check "no autostart marker is left behind" "0" "$(grep -c -- "$AUTOMARK" "$CONFIG/hypr/autostart.lua")"
check "the user's own line survives" "1" "$(grep -c -- '-- my own hyprland.lua' "$CONFIG/hypr/hyprland.lua")"

# ── a foreign file is left alone ───────────────────────────────────────────────
seed_user_config
printf -- '-- hand-written, not ours\n' > "$CONFIG/hypr/keepassxc-bindings.lua"
run --uninstall >"$TMP/out" 2>&1
check "uninstalling with a foreign fragment succeeds" "0" "$?"
check_file "$CONFIG/hypr/keepassxc-bindings.lua" "a bindings fragment that is not ours is left alone"
check "and the refusal is reported" "1" "$(grep -cF -- 'is not the shipped copy' "$TMP/out")"

# A foreign require line (someone else's fragment) is not this script's to touch.
seed_user_config
printf -- '-- my own hyprland.lua\nrequire("hypr.my-own-bindings")\n' > "$CONFIG/hypr/hyprland.lua"
before="$(sha256sum "$CONFIG/hypr/hyprland.lua" | cut -d' ' -f1)"
run --uninstall >/dev/null 2>&1
check "a foreign require line leaves the config byte-identical" "$before" \
  "$(sha256sum "$CONFIG/hypr/hyprland.lua" | cut -d' ' -f1)"

# A config holding nothing but our line is cleaned up too (grep -v selects nothing).
seed_user_config
printf '%s\n' "$REQ" > "$CONFIG/hypr/hyprland.lua"
run --uninstall >/dev/null 2>&1
check "a config holding only our line is cleaned up" "0" "$(grep -cF -- "$REQ" "$CONFIG/hypr/hyprland.lua")"

# A second full cycle is still byte-identical — a stacked marker would show here.
seed_user_config
run >/dev/null 2>&1; run --uninstall >/dev/null 2>&1
run >/dev/null 2>&1; run --uninstall >/dev/null 2>&1
check "a second cycle leaves hyprland.lua byte-identical" "$before_hypr" \
  "$(sha256sum "$CONFIG/hypr/hyprland.lua" | cut -d' ' -f1)"
check "a second cycle leaves autostart.lua byte-identical" "$before_auto" \
  "$(sha256sum "$CONFIG/hypr/autostart.lua" | cut -d' ' -f1)"

# ── packages the plugin depends on are never touched by --uninstall ─────────────
seed_user_config
run >/dev/null 2>&1
: > "$LOG"
run --uninstall >/dev/null 2>&1
check "no package is removed by --uninstall" "0" "$(grep -c -- 'pacman -R' "$LOG")"
check "no package is added by --uninstall" "0" "$(grep -c -- 'pkg add' "$LOG")"

printf '\nuninstall round-trip: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
