#!/bin/bash
# omarchy-keepassxc install script

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"

echo "omarchy-keepassxc: installing from $PLUGIN_DIR"

# ── 1. Replace KeePass2 with KeePassXC ────────────────────────────────────────
# Remove KeePass2 (Mono) if installed — it conflicts with KeePassXC browser integration
if pacman -Qi keepass &>/dev/null; then
  echo "  Removing KeePass2 (replaced by KeePassXC)..."
  # Kill any running KeePass2 instance first
  pkill -f "KeePass.exe" 2>/dev/null || true
  sleep 1
  if [[ $EUID -eq 0 ]]; then
    pacman -Rs --noconfirm keepass 2>/dev/null || pacman -R --noconfirm keepass 2>/dev/null || true
  elif command -v sudo >/dev/null 2>&1; then
    sudo pacman -Rs --noconfirm keepass 2>/dev/null || sudo pacman -R --noconfirm keepass 2>/dev/null || true
  fi
  echo "  KeePass2 removed."
fi

# Install KeePassXC
omarchy pkg add keepassxc
echo "  KeePassXC installed."

# ── 2. Open existing database in KeePassXC ────────────────────────────────────
# If user has a .kdbx file that was used with KeePass2, KeePassXC reads the
# same format — no migration needed. Just open it.
KDBX=$(find "$HOME" -name "*.kdbx" -not -path "*/\.Trash/*" 2>/dev/null | head -1)
if [[ -n "$KDBX" ]]; then
  echo "  Found database: $KDBX"
  echo "  KeePassXC reads KeePass2 .kdbx files directly — no migration needed."
fi

# ── 3. Install pynacl (for qutebrowser integration) ───────────────────────────
if ! /usr/bin/python3 -c "import nacl" 2>/dev/null; then
  omarchy pkg add python-pynacl 2>/dev/null || pip install --break-system-packages pynacl 2>/dev/null || true
fi
echo "  pynacl available."

# ── 4. Add KeePassXC to autostart ─────────────────────────────────────────────
AUTOSTART="$HYPR_CONFIG_DIR/autostart.lua"
if [[ -f "$AUTOSTART" ]] && ! grep -q "keepassxc" "$AUTOSTART"; then
  printf '\n-- omarchy-keepassxc: start KeePassXC at login\no.launch_on_start("keepassxc")\n' >> "$AUTOSTART"
  echo "  Added KeePassXC to autostart."
elif grep -q "keepassxc" "${AUTOSTART:-/dev/null}" 2>/dev/null; then
  echo "  KeePassXC already in autostart."
else
  echo "  No autostart.lua found — add manually: o.launch_on_start(\"keepassxc\")"
fi

# ── 5. Wire OS keybindings into Hyprland ──────────────────────────────────────
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

# ── 5b. Theme integration ─────────────────────────────────────────────────────
# KeePassXC does not follow the Omarchy palette and its "auto" theme shows the
# unlock window light, so set its ApplicationTheme to match the active theme
# and keep it in sync on future theme switches.
chmod +x "$PLUGIN_DIR/hooks/theme-set" "$PLUGIN_DIR/bin/keepassxc-theme.py"
CURRENT_THEME=$(omarchy theme current 2>/dev/null || true)
if [[ -n "$CURRENT_THEME" ]]; then
  bash "$PLUGIN_DIR/hooks/theme-set" "$CURRENT_THEME" || true
  echo "  Set KeePassXC theme to match: $CURRENT_THEME"
fi
omarchy hook install theme-set "$PLUGIN_DIR/hooks/theme-set"
echo "  Installed theme-set hook."

# ── 6. Reload Hyprland ────────────────────────────────────────────────────────
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 && echo "  Hyprland reloaded." || true
else
  echo "  Run 'hyprctl reload' to activate keybindings."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Done!"
echo ""
if [[ -n "${KDBX:-}" ]]; then
  echo "Your database: $KDBX"
  echo "Open it in KeePassXC — the format is identical to KeePass2, no migration needed."
  echo ""
fi
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
