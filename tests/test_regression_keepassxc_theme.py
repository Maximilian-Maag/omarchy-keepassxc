"""Regression tests for bin/keepassxc-theme.py.

Each test names the bug it pins. They are deliberately about the *line-based*
editor's edge cases, which is where the real defects lived: configparser would
mangle the KeeShare XML blob, and naive editing duplicates or misplaces the key.
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
    spec = importlib.util.spec_from_file_location("keepassxc_theme_reg", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["keepassxc_theme_reg"] = mod
    spec.loader.exec_module(mod)
    return mod


class ThemeRegressionCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_theme_module()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config_home = pathlib.Path(self.tmp.name) / "config"
        self.ini = self.config_home / "keepassxc" / "keepassxc.ini"

    def run_main(self, theme):
        old = {k: os.environ.get(k) for k in ("XDG_CONFIG_HOME", "HOME")}
        sys.argv = ["keepassxc-theme.py", theme]
        os.environ["XDG_CONFIG_HOME"] = str(self.config_home)
        os.environ["HOME"] = str(pathlib.Path(self.tmp.name) / "home")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                return self.mod.main()
        finally:
            sys.argv = ["keepassxc-theme.py"]
            for key, value in old.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    def write_ini(self, text):
        self.ini.parent.mkdir(parents=True, exist_ok=True)
        self.ini.write_text(text)

    def test_keeshare_blob_is_never_reformatted(self):
        # Bug pinned: a configparser round-trip collapses/escapes the XML blob
        # (percent signs, '=' and quotes), corrupting KeeShare state.
        blob = "<KeeShare>team=100%&x=\"y\"=z</KeeShare>"
        self.write_ini(f"[KeeShare]\nActive={blob}\n[GUI]\nFoo=bar\n")
        self.assertEqual(self.run_main("dark"), 0)
        self.assertIn(blob, self.ini.read_text())

    def test_running_twice_does_not_append_a_second_key(self):
        # Bug pinned: the key was appended on every run, growing the file.
        self.assertEqual(self.run_main("dark"), 0)
        first = self.ini.read_text()
        self.assertEqual(self.run_main("dark"), 0)
        second = self.ini.read_text()
        self.assertEqual(second.count("ApplicationTheme="), 1)
        self.assertEqual(first, second)

    def test_existing_newline_terminated_key_is_replaced_not_duplicated(self):
        # Bug pinned: matching only the exact string left a trailing-CR variant.
        self.write_ini("[GUI]\r\nApplicationTheme=light\r\n")
        self.assertEqual(self.run_main("dark"), 0)
        self.assertEqual(self.ini.read_text().count("ApplicationTheme="), 1)
        self.assertIn("ApplicationTheme=dark", self.ini.read_text())

    def test_key_lands_before_the_next_header_not_at_end_of_file(self):
        # Bug pinned: inserting at EOF put the key outside [GUI], so KeePassXC
        # never read it when another section followed.
        self.write_ini("[GUI]\nFoo=1\n[KeeShare]\nActive=blob\n")
        self.assertEqual(self.run_main("dark"), 0)
        lines = self.ini.read_text().splitlines()
        self.assertLess(lines.index("ApplicationTheme=dark"), lines.index("[KeeShare]"))

    def test_key_inserted_into_an_existing_empty_gui_section(self):
        # Bug pinned: an existing but empty [GUI] got a second [GUI] header.
        self.write_ini("[GUI]\n[Other]\nBar=2\n")
        self.assertEqual(self.run_main("dark"), 0)
        text = self.ini.read_text()
        self.assertEqual(text.count("[GUI]"), 1)
        self.assertIn("ApplicationTheme=dark", text)

    def test_bracket_ending_value_is_not_mistaken_for_a_header(self):
        # Bug pinned: scanning for a lone trailing ']' treated a value like a
        # section boundary and inserted the key in the wrong place.
        self.write_ini("[GUI]\nPattern=[a-z]\nFoo=1\n")
        self.assertEqual(self.run_main("dark"), 0)
        lines = self.ini.read_text().splitlines()
        self.assertIn("Pattern=[a-z]", lines)
        self.assertLess(lines.index("Pattern=[a-z]"), lines.index("ApplicationTheme=dark"))


if __name__ == "__main__":
    unittest.main()