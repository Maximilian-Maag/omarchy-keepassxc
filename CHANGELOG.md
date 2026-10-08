# Changelog

All notable changes to omarchy-keepassxc are documented here.

## [1.2.0] — 2026-10-08

Feature set as of this release (earlier versions predate this changelog):

- Replaces KeePass2 with KeePassXC — removes `keepass` and `mono`, installs
  `keepassxc` via `omarchy pkg add`.
- No migration step: KeePassXC reads existing `.kdbx` files directly
  (`~/Nextcloud/Dokumente/private-accounts.kdbx` by default).
- `Super+Shift+/` launches or focuses KeePassXC, replacing the 1Password default.
- Starts at login on workspace 5, silently (does not switch the active workspace).
- Follows the Omarchy light/dark mode through a `theme-set` hook, since KeePassXC
  has no Omarchy palette support of its own.
- Browser integration with qutebrowser via `qute-keepassxc`.
