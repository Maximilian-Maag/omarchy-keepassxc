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
  # Only report success when the package is actually gone: the removal is best
  # effort (a locked db, a partial transaction), so a silent `|| true` would lie.
  removed=false
  if [[ $EUID -eq 0 ]]; then
    if pacman -Rs --noconfirm keepass 2>/dev/null || pacman -R --noconfirm keepass 2>/dev/null; then
      removed=true
    fi
  elif command -v sudo >/dev/null 2>&1; then
    if sudo pacman -Rs --noconfirm keepass 2>/dev/null || sudo pacman -R --noconfirm keepass 2>/dev/null; then
      removed=true
    fi
  fi
  if [[ $removed == true ]]; then
    echo "  KeePass2 removed."
  else
    echo "  WARNING: could not remove KeePass2 — remove it manually: sudo pacman -R keepass"
  fi

  # mono is KeePass2's runtime. Remove it too — but only when it is now an
  # orphan (nothing else depends on it, and it was not installed explicitly),
  # so a mono the user actually wants is never touched.
  if pacman -Qi mono &>/dev/null && pacman -Qdtq 2>/dev/null | grep -qx mono; then
    removed_mono=false
    if [[ $EUID -eq 0 ]]; then
      if pacman -Rns --noconfirm mono 2>/dev/null; then removed_mono=true; fi
    elif command -v sudo >/dev/null 2>&1; then
      if sudo pacman -Rns --noconfirm mono 2>/dev/null; then removed_mono=true; fi
    fi
    if [[ $removed_mono == true ]]; then
      echo "  Removed mono (KeePass2's runtime, no longer needed)."
    fi
  fi
fi

# Install KeePassXC
if omarchy pkg add keepassxc; then
  echo "  KeePassXC installed."
else
  echo "  WARNING: could not install KeePassXC — install it manually: omarchy pkg add keepassxc"
fi

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
if /usr/bin/python3 -c "import nacl" 2>/dev/null; then
  echo "  pynacl available."
else
  echo "  WARNING: pynacl is not available — install it for qutebrowser integration: omarchy pkg add python-pynacl"
fi

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
chmod +x "$PLUGIN_DIR/hooks/keepassxc-theme-set" "$PLUGIN_DIR/bin/keepassxc-theme.py"
CURRENT_THEME=$(omarchy theme current 2>/dev/null || true)
# The hook is a documented no-op for a theme whose colors.toml cannot be found
# (it exits 0 without writing anything), so success must be reported only when
# the theme is actually locatable and the hook applied it.
theme_colors_file() { # theme -> colors.toml path on stdout, or empty
  local t base
  t=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  for base in "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes" "/usr/share/omarchy/themes"; do
    if [[ -f "$base/$t/colors.toml" ]]; then printf '%s\n' "$base/$t/colors.toml"; return 0; fi
  done
  return 1
}
if [[ -n "$CURRENT_THEME" ]]; then
  if ! theme_colors_file "$CURRENT_THEME" >/dev/null; then
    echo "  WARNING: theme '$CURRENT_THEME' has no colors.toml — KeePassXC theme left unchanged."
  elif OMARCHY_KEEPASSXC_DIR="$PLUGIN_DIR" bash "$PLUGIN_DIR/hooks/keepassxc-theme-set" "$CURRENT_THEME"; then
    echo "  Set KeePassXC theme to match: $CURRENT_THEME"
  else
    echo "  WARNING: could not set KeePassXC theme for: $CURRENT_THEME"
  fi
fi
# Guard the hook install the way the sibling omarchy-voxtype does: a missing
# `omarchy` must not abort the install under `set -e` before the summary runs.
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/keepassxc-theme-set"
  echo "  Installed theme-set hook (as keepassxc-theme-set)."
else
  echo "  WARNING: omarchy not found — install the hook manually: omarchy hook install theme-set $PLUGIN_DIR/hooks/keepassxc-theme-set"
fi

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
