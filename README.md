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
| Theme | Follows the Omarchy light/dark mode via a `theme-set` hook (KeePassXC has no Omarchy palette support, so it matches dark/light) |
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

<!-- policy-as-code -->

## Policy as code

Policies that only live in prose drift. This repository enforces its own in
`tools/policy_check.py` (dependency-free), configured by `policy.json`:

    python3 tools/policy_check.py            # every tracked file
    python3 tools/policy_check.py --changed  # only what you changed (pre-commit)
    python3 tools/policy_check.py --ci       # changed vs the base branch (CI)

`--changed` is wired into `.githooks/pre-commit` and the checks also run in
`.github/workflows/policy.yml`, so a violation fails the commit or the pull
request. After cloning, enable the hook once:

    git config core.hooksPath .githooks

Documented exceptions belong in `policy.json` under `allow`, each with a reason —
an exception you can read is a decision; a check nobody runs is decoration.
