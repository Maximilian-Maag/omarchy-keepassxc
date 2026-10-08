"""Unit tests: bin/keepassxc-theme.py's line-based keepassxc.ini editing.

The script is loaded with importlib under a non-__main__ name so its top-level
guard does not fire; main() is then called directly with a temporary
XDG_CONFIG_HOME. That exercises the shipped source — no re-implementation.
"""
import contextlib
import importlib.util
import io
import os
import pathlib
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = REPO / "bin/keepassxc-theme.py"


def load_theme_module():
    spec = importlib.util.spec_from_file_location("keepassxc_theme", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["keepassxc_theme"] = mod
    spec.loader.exec_module(mod)
    return mod


class ThemeEditorCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_theme_module()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config_home = pathlib.Path(self.tmp.name) / "config"
        self.ini = self.config_home / "keepassxc" / "keepassxc.ini"

    # ── helpers ───────────────────────────────────────────────────────────
    def run_main(self, *args):
        """Call main() with argv/XDG_CONFIG_HOME/HOME set, returning (rc, stdout)."""
        old = {k: os.environ.get(k) for k in ("XDG_CONFIG_HOME", "HOME")}
        sys.argv = ["keepassxc-theme.py", *args]
        os.environ["XDG_CONFIG_HOME"] = str(self.config_home)
        os.environ["HOME"] = str(pathlib.Path(self.tmp.name) / "home")
        out, err = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = self.mod.main()
        finally:
            sys.argv = ["keepassxc-theme.py"]
            for key, value in old.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        return rc, out.getvalue(), err.getvalue()

    def write_ini(self, text):
        self.ini.parent.mkdir(parents=True, exist_ok=True)
        self.ini.write_text(text)

    def read_ini(self):
        return self.ini.read_text()

    def theme_lines(self):
        return [l for l in self.read_ini().splitlines()
                if l.startswith("ApplicationTheme")]

    # ── the accepted values ───────────────────────────────────────────────
    def test_every_valid_value_is_written(self):
        for theme in self.mod.VALID:
            with self.subTest(theme=theme):
                self.config_home = pathlib.Path(self.tmp.name) / f"cfg-{theme}"
                self.ini = self.config_home / "keepassxc" / "keepassxc.ini"
                rc, _, _ = self.run_main(theme)
                self.assertEqual(rc, 0)
                self.assertIn(f"ApplicationTheme={theme}", self.read_ini())

    def test_missing_argument_is_a_usage_error_and_writes_nothing(self):
        rc, _, err = self.run_main()
        self.assertEqual(rc, 2)
        self.assertIn("usage:", err)
        self.assertFalse(self.ini.exists())

    def test_invalid_value_is_a_usage_error_and_writes_nothing(self):
        rc, _, err = self.run_main("neon")
        self.assertEqual(rc, 2)
        self.assertIn("usage:", err)
        self.assertFalse(self.ini.exists())

    # ── file shape ────────────────────────────────────────────────────────
    def test_creates_the_gui_section_when_the_file_is_absent(self):
        rc, out, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        text = self.read_ini()
        self.assertIn("[GUI]", text)
        self.assertIn("ApplicationTheme=dark", text)
        self.assertIn("ApplicationTheme=dark", out)

    def test_appends_a_gui_section_when_the_file_has_other_sections_only(self):
        # A keepassxc.ini can exist with [General]/[KeeShare] but no [GUI] yet.
        self.write_ini("[General]\nLastDir=/data\n")
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        text = self.read_ini()
        self.assertEqual(text.count("[GUI]"), 1)
        self.assertIn("LastDir=/data", text)
        self.assertIn("ApplicationTheme=dark", text)

    def test_duplicate_gui_sections_never_duplicate_the_key(self):
        # Defensive: an existing file with two [GUI] headers must still end up
        # with exactly one ApplicationTheme line.
        self.write_ini("[GUI]\nFoo=1\n[GUI]\nBar=2\n")
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        lines = self.read_ini().splitlines()
        self.assertEqual(self.theme_lines(), ["ApplicationTheme=dark"])
        self.assertEqual(lines.count("[GUI]"), 2)

    def test_replaces_an_existing_value_in_place(self):
        self.write_ini("[GUI]\nApplicationTheme=light\nFoo=bar\n")
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        lines = self.read_ini().splitlines()
        self.assertEqual(self.theme_lines(), ["ApplicationTheme=dark"])
        self.assertIn("Foo=bar", lines)

    def test_inserts_before_the_next_header_so_it_stays_in_gui(self):
        self.write_ini("[GUI]\nFoo=1\n[Other]\nBar=2\n")
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        lines = self.read_ini().splitlines()
        self.assertEqual(lines.count("ApplicationTheme=dark"), 1)
        self.assertLess(lines.index("Foo=1"), lines.index("ApplicationTheme=dark"))
        self.assertLess(lines.index("ApplicationTheme=dark"), lines.index("[Other]"))
        self.assertIn("Bar=2", lines)

    def test_a_value_ending_in_a_bracket_is_not_a_section_header(self):
        self.write_ini("[GUI]\nFoo=1\nUrl=[x]\n[Other]\nBar=2\n")
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        lines = self.read_ini().splitlines()
        self.assertEqual(lines.count("ApplicationTheme=dark"), 1)
        self.assertLess(lines.index("Url=[x]"), lines.index("ApplicationTheme=dark"))
        self.assertLess(lines.index("ApplicationTheme=dark"), lines.index("[Other]"))

    def test_the_edit_is_idempotent(self):
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        rc, _, _ = self.run_main("dark")
        self.assertEqual(rc, 0)
        self.assertEqual(self.theme_lines(), ["ApplicationTheme=dark"])

    def test_unrelated_keys_and_the_keeshare_blob_survive(self):
        blob = ('<KeeShare><group><name>Team</name>'
                '<secret>aGVsbG8=</secret></group></KeeShare>')
        self.write_ini(f"[KeeShare]\nActive={blob}\n\n[GUI]\nFoo=1\n")
        rc, _, _ = self.run_main("light")
        self.assertEqual(rc, 0)
        after = self.read_ini()
        self.assertIn(blob, after)
        self.assertIn("Foo=1", after)
        self.assertIn("ApplicationTheme=light", after)

    def test_switching_back_and_forth_never_duplicates(self):
        for theme in ("dark", "light", "auto", "classic", "dark"):
            rc, _, _ = self.run_main(theme)
            self.assertEqual(rc, 0)
        self.assertEqual(self.theme_lines(), ["ApplicationTheme=dark"])


if __name__ == "__main__":
    unittest.main()