"""Integration tests: hooks/theme-set end-to-end in a fake environment.

The real hook is executed as a subprocess with a temporary HOME and
XDG_CONFIG_HOME, a fake Omarchy theme tree, and stub pgrep/pkill/setsid/
uwsm-app/sleep binaries on PATH so no live KeePassXC is ever touched. The
observable effect — keepassxc.ini, and which stubs were invoked — is asserted.
"""
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
HOOK = REPO / "hooks/theme-set"

PASSTHROUGH_PY = """#!/bin/bash
echo "python3 $*" >> "$STUB_LOG"
exec "{real_py}" "$@"
"""

STUBS = {
    "pgrep": '#!/bin/bash\necho "pgrep $*" >> "$STUB_LOG"\nexit "${STUB_PGREP_RC:-1}"\n',
    "pkill": '#!/bin/bash\necho "pkill $*" >> "$STUB_LOG"\nexit "${STUB_PKILL_RC:-0}"\n',
    "setsid": '#!/bin/bash\necho "setsid $*" >> "$STUB_LOG"\nexit 0\n',
    "uwsm-app": '#!/bin/bash\necho "uwsm-app $*" >> "$STUB_LOG"\nexit 0\n',
    "sleep": '#!/bin/bash\necho "sleep $*" >> "$STUB_LOG"\nexit 0\n',
}


class ThemeSetIntegrationCase(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="kp-hook-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.home = self.tmp / "home"
        self.config = self.tmp / "config"
        self.log = self.tmp / "stub.log"
        self.home.mkdir()
        (self.config / "omarchy/themes").mkdir(parents=True)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        real_py = shutil.which("python3")
        assert real_py, "python3 must be on PATH to run the hook"
        for name, body in STUBS.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        py = self.bin / "python3"
        py.write_text(PASSTHROUGH_PY.format(real_py=real_py))
        py.chmod(py.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    # ── helpers ───────────────────────────────────────────────────────────
    def make_theme(self, name, mode, stock=False):
        base = self.config / "omarchy/themes" if not stock else self.tmp / "stock"
        d = base / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "colors.toml").write_text(f'mode = "{mode}"\nbackground = "#111111"\n')

    def ini_path(self):
        return self.config / "keepassxc/keepassxc.ini"

    def write_ini(self, text):
        self.ini_path().parent.mkdir(parents=True, exist_ok=True)
        self.ini_path().write_text(text)

    def logged(self):
        return self.log.read_text() if self.log.exists() else ""

    def run_hook(self, theme=None, pgrep_rc=None):
        env = dict(os.environ)
        env["HOME"] = str(self.home)
        env["XDG_CONFIG_HOME"] = str(self.config)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STUB_LOG"] = str(self.log)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        if pgrep_rc is not None:
            env["STUB_PGREP_RC"] = str(pgrep_rc)
        argv = ["bash", str(HOOK)] + ([theme] if theme is not None else [])
        return subprocess.run(argv, env=env, cwd=str(REPO), capture_output=True, text=True)

    # ── mode mapping ──────────────────────────────────────────────────────
    def test_dark_theme_writes_dark(self):
        self.make_theme("nord", "dark")
        proc = self.run_hook("Nord")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("[GUI]", self.ini_path().read_text())
        self.assertIn("ApplicationTheme=dark", self.ini_path().read_text())

    def test_light_theme_writes_light(self):
        self.make_theme("solarized", "light")
        proc = self.run_hook("solarized")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("ApplicationTheme=light", self.ini_path().read_text())

    def test_mode_matching_is_case_insensitive_and_any_other_mode_is_dark(self):
        self.make_theme("mixed", "LIGHT")
        self.assertEqual(self.run_hook("mixed").returncode, 0)
        self.assertIn("ApplicationTheme=light", self.ini_path().read_text())
        self.make_theme("weird", "sepia")
        self.assertEqual(self.run_hook("weird").returncode, 0)
        self.assertIn("ApplicationTheme=dark", self.ini_path().read_text())

    # ── no-op paths ───────────────────────────────────────────────────────
    def test_unknown_theme_is_a_noop(self):
        proc = self.run_hook("does-not-exist")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(self.ini_path().exists())
        self.assertNotIn("python3", self.logged())

    def test_empty_theme_is_a_noop(self):
        self.make_theme("nord", "dark")
        proc = self.run_hook("")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(self.ini_path().exists())
        self.assertNotIn("python3", self.logged())

    # ── the real editing path ─────────────────────────────────────────────
    def test_existing_keys_survive_the_theme_write(self):
        self.make_theme("nord", "dark")
        self.write_ini("[General]\nLastDir=/data\n\n[GUI]\nFoo=bar\n")
        self.assertEqual(self.run_hook("nord").returncode, 0)
        text = self.ini_path().read_text()
        self.assertIn("LastDir=/data", text)
        self.assertIn("Foo=bar", text)
        self.assertIn("ApplicationTheme=dark", text)

    # ── restart policy ────────────────────────────────────────────────────
    def test_changed_mode_restarts_a_running_keepassxc(self):
        self.make_theme("nord", "light")
        self.write_ini("[GUI]\nApplicationTheme=dark\n")
        self.assertEqual(self.run_hook("nord", pgrep_rc=0).returncode, 0)
        self.assertIn("pkill", self.logged())

    def test_unchanged_mode_does_not_restart(self):
        self.make_theme("nord", "dark")
        self.write_ini("[GUI]\nApplicationTheme=dark\n")
        self.assertEqual(self.run_hook("nord", pgrep_rc=0).returncode, 0)
        self.assertNotIn("pkill", self.logged())

    def test_changed_mode_but_not_running_does_not_restart(self):
        self.make_theme("nord", "light")
        self.write_ini("[GUI]\nApplicationTheme=dark\n")
        self.assertEqual(self.run_hook("nord", pgrep_rc=1).returncode, 0)
        self.assertNotIn("pkill", self.logged())


if __name__ == "__main__":
    unittest.main()