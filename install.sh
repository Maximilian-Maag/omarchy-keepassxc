#!/bin/bash
# omarchy-keepassxc install script

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"

echo "omarchy-keepassxc: installing from $PLUGIN_DIR"

# ── 1. Install KeePassXC ──────────────────────────────────────────────────────
omarchy pkg add keepassxc
echo "  KeePassXC installed."

# ── 2. Install pynacl (for qutebrowser integration) ───────────────────────────
if ! /usr/bin/python3 -c "import nacl" 2>/dev/null; then
  omarchy pkg add python-pynacl 2>/dev/null || pip install --break-system-packages pynacl 2>/dev/null || true
fi
echo "  pynacl available."

# ── 3. Enable Browser Integration via autostart ───────────────────────────────
# KeePassXC browser integration requires the app to be running.
# Add it to Hyprland autostart if not already there.
AUTOSTART="$HYPR_CONFIG_DIR/autostart.lua"
if [[ -f "$AUTOSTART" ]] && ! grep -q "keepassxc" "$AUTOSTART"; then
  printf '\n-- omarchy-keepassxc: start KeePassXC at login\no.launch_on_start("keepassxc")\n' >> "$AUTOSTART"
  echo "  Added KeePassXC to autostart."
elif grep -q "keepassxc" "${AUTOSTART:-/dev/null}" 2>/dev/null; then
  echo "  KeePassXC already in autostart."
else
  echo "  No autostart.lua found — add manually: o.launch_on_start(\"keepassxc\")"
fi

# ── 4. Wire OS keybindings into Hyprland ──────────────────────────────────────
if [[ ! -f "$HYPR_MAIN" ]]; then
  echo "  WARNING: $HYPR_MAIN not found — skipping keybinding wiring."
else
  cp "$PLUGIN_DIR/bin/bindings.lua" "$HYPR_CONFIG_DIR/keepassxc-bindings.lua"
  if ! grep -q "keepassxc-bindings" "$HYPR_MAIN"; then
    printf '\n-- omarchy-keepassxc keybindings\nrequire("hypr.keepassxc-bindings")\n' >> "$HYPR_MAIN"
    echo "  Wired keybindings into $HYPR_MAIN"
  else
    echo "  Keybindings already wired (updated)."
  fi
fi

# ── 5. Reload Hyprland ────────────────────────────────────────────────────────
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 && echo "  Hyprland reloaded." || true
else
  echo "  Run 'hyprctl reload' to activate keybindings."
fi

# ── 6. Print setup instructions ───────────────────────────────────────────────
echo ""
echo "Done!"
echo ""
echo "Next: enable Browser Integration in KeePassXC:"
echo "  Tools > Settings > Browser Integration > Enable browser integration"
echo "  Tick: Chromium-based browsers (for qutebrowser)"
echo ""
echo "Keybindings:"
echo "  Super + Shift + /  — launch or focus KeePassXC"
echo ""
echo "Qutebrowser password fill (if omarchy-qutebrowser is installed):"
echo "  pw           (normal mode) — fill password"
echo "  Alt+Shift+U  (insert mode) — fill password"
echo "  ,kp          (normal mode) — check setup status"
