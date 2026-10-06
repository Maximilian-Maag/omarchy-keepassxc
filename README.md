# omarchy-keepassxc

Replaces KeePass2 with [KeePassXC](https://keepassxc.org/) for [Omarchy](https://omarchy.org/).

## What it does

| Step | Action |
|------|--------|
| Removes KeePass2 | Uninstalls `keepass` and `mono` |
| Installs KeePassXC | Via `omarchy pkg add keepassxc` |
| No migration | KeePassXC reads existing `.kdbx` files directly |
| Keybinding | `Super+Shift+/` launches or focuses KeePassXC (replaces 1Password default) |
| Autostart | KeePassXC starts at login via `autostart.lua` |
| Workspace | Opens on workspace 5 at login (silent — does not switch your active workspace) |
| Browser integration | Works with qutebrowser via `qute-keepassxc --insecure` |

## Installation

```bash
omarchy plugin add https://github.com/Maximilian-Maag/omarchy-keepassxc --yes
bash ~/.config/omarchy/plugins/Maximilian-Maag.keepassxc/install.sh
```

## After install

Enable Browser Integration in KeePassXC:

```
Tools > Settings > Browser Integration
  ✓ Enable browser integration
  ✓ Chromium-based browsers
```

Then in qutebrowser, navigate to a login page and press `pw` (normal mode) or `Alt+Shift+U` (insert mode). KeePassXC will ask you to confirm the connection on first use.

Use `,kp` in qutebrowser to check the setup status at any time.

## Keybindings

| Key | Action |
|-----|--------|
| `Super+Shift+/` | Launch or focus KeePassXC |
| `pw` | Fill password (qutebrowser normal mode) |
| `Alt+Shift+U` | Fill password (qutebrowser insert mode) |
| `,kp` | Check KeePassXC setup status |

## License

MIT
