# Changelog

All notable changes to omarchy-keepassxc are documented here.

## [1.3.3] — 2026-11-22

### Fixed
- **`install.sh` no longer aborts while it looks for an existing database.**
  `KDBX=$(find "$HOME" -name "*.kdbx" … | head -1)` failed under
  `set -euo pipefail` for two independent reasons: `find` exits 1 whenever it
  cannot enter a directory — a docker `overlay2` under `~/.local/share` is
  enough, because `2>/dev/null` hides the message but not the status — and
  `head -1` closes the pipe while `find` still has output, so `find` dies of
  SIGPIPE (exit 141 with 3000 databases, exit 0 with 2). Either failure fails the
  assignment and `set -e` ends the run after the KeePassXC install but before the
  autostart entry and the keybindings fragment, so KeePassXC never started at
  login and `Super+Shift+/` was never bound while the run looked like an ordinary
  failure. Fixed with `find … -print -quit` (stops at the first match) plus
  `|| true`; the shell tests now cover both an unreadable directory and a home
  with 1500 databases.

## [1.3.2] — 2026-11-02

### Added
- **A way to make KeePassXC use the desktop palette** (`docs/keepass-patch/`).
  KeePassXC cannot follow the Omarchy palette: its themes are `auto` (renders
  light), `light`, `dark` (its own grey) and `classic`, the colours are a C++
  `QPalette`, and it ignores `QT_QPA_PLATFORMTHEME=gtk3` because its own
  stylesheet always wins. `render-palette.py` rewrites that palette from the
  theme's `colors.toml`; `build-patched-keepassxc.sh` builds a patched Arch
  package. Every substitution is asserted, so a KeePassXC release that changes
  the files fails loudly instead of shipping a half-themed app. This is a
  rebuild, like the QtWebEngine patch in omarchy-qutebrowser: re-run it after a
  stock upgrade. Seven unit tests cover the mapping, idempotency, `--check`,
  and the guard rails.

## [1.3.1] — 2026-10-28

### Fixed
- **The `theme-set` hook did nothing once installed, and its name collided** (#1). It
  resolved its plugin with `$(dirname "$BASH_SOURCE")/..`, which is the hooks directory
  after `omarchy hook install` copies it there, so `"$PLUGIN_DIR/bin/keepassxc-theme.py"`
  did not exist and — under `set -euo pipefail` — the hook aborted before writing
  `ApplicationTheme`. It now self-locates (`$OMARCHY_KEEPASSXC_DIR` → the installed plugin
  dirs → the dev checkout) and fails loudly when the plugin is absent. Renamed to
  `hooks/keepassxc-theme-set`: the bare basename `theme-set` is shared with
  omarchy-thunderbird / -contacts / -qutebrowser and only the last installed survives.
- **The mutation runner ignored every declared equivalent mutant** (#2). Its filter looked
  up `r.get("kind")` while the survivor record stores `"operator"`, so the `equivalent`
  list was silently inert and an unkillable mutant stayed in the denominator. It now reads
  `r.get("operator")`, matching the sibling repos, with a regression test driving the real
  runner over a fixture.

## [1.3.0] — 2026-10-08

### Added
- Test harness: policy as code plus unit, regression, integration, shell and
  mutation tests, with `tools/run_tests.sh` as the single entry point and CI
  running it (.github/workflows/test.yml). Mutation score is enforced at >= 0.80,
  and no source file may be left neither mutated nor exempted with a reason.

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
