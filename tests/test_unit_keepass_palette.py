"""Unit tests for docs/keepass-patch/render-palette.py.

The generator rewrites KeePassXC's C++ QPalette from an Omarchy theme. These
tests run it against a fixture source tree shaped like the real files, and pin
the properties that matter: the palette actually reaches the C++, the rewrite is
idempotent, --check does not write, and an unknown source is refused loudly.
"""

import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = REPO / "docs/keepass-patch/render-palette.py"

THEME = """\
mode = "dark"
accent = "#ffcc00"
selection = "#33301a"
muted = "#3a3520"
background = "#000000"
lighter_background = "#1a1810"
foreground = "#ffd700"
dark_foreground = "#8a7300"
light_foreground = "#ffe680"
bright_foreground = "#fff2b3"
"""

# A trimmed but structurally faithful DarkStyle.cpp: the roles the patcher maps.
CPP = """\
QPalette DarkStyle::standardPalette() const
{
    auto palette = BaseStyle::standardPalette();
    palette.setColor(QPalette::Active, QPalette::Window, QRgb(0x3B3B3D));
    palette.setColor(QPalette::Inactive, QPalette::Window, QRgb(0x404042));
    palette.setColor(QPalette::Disabled, QPalette::Window, QRgb(0x424242));
    palette.setColor(QPalette::Active, QPalette::WindowText, QRgb(0xCACBCE));
    palette.setColor(QPalette::Inactive, QPalette::WindowText, QRgb(0xC8C8C6));
    palette.setColor(QPalette::Disabled, QPalette::WindowText, QRgb(0x707070));
    palette.setColor(QPalette::Active, QPalette::Text, QRgb(0xCACBCE));
    palette.setColor(QPalette::Inactive, QPalette::Text, QRgb(0xC8C8C6));
    palette.setColor(QPalette::Disabled, QPalette::Text, QRgb(0x707070));
    palette.setColor(QPalette::Active, QPalette::PlaceholderText, QRgb(0x7D7D82));
    palette.setColor(QPalette::Inactive, QPalette::PlaceholderText, QRgb(0x87888C));
    palette.setColor(QPalette::Disabled, QPalette::PlaceholderText, QRgb(0x737373));
    palette.setColor(QPalette::Active, QPalette::BrightText, QRgb(0x252627));
    palette.setColor(QPalette::Inactive, QPalette::BrightText, QRgb(0x2D2D2F));
    palette.setColor(QPalette::Disabled, QPalette::BrightText, QRgb(0x333333));
    palette.setColor(QPalette::Active, QPalette::Base, QRgb(0x27272A));
    palette.setColor(QPalette::Inactive, QPalette::Base, QRgb(0x2A2A2D));
    palette.setColor(QPalette::Disabled, QPalette::Base, QRgb(0x343437));
    palette.setColor(QPalette::Active, QPalette::AlternateBase, QRgb(0x2C2C30));
    palette.setColor(QPalette::Inactive, QPalette::AlternateBase, QRgb(0x2B2B2F));
    palette.setColor(QPalette::Disabled, QPalette::AlternateBase, QRgb(0x36363A));
    palette.setColor(QPalette::All, QPalette::ToolTipBase, QRgb(0x2D532D));
    palette.setColor(QPalette::All, QPalette::ToolTipText, QRgb(0xBFBFBF));
    palette.setColor(QPalette::Active, QPalette::Button, QRgb(0x28282B));
    palette.setColor(QPalette::Inactive, QPalette::Button, QRgb(0x28282B));
    palette.setColor(QPalette::Disabled, QPalette::Button, QRgb(0x2B2A2A));
    palette.setColor(QPalette::Active, QPalette::ButtonText, QRgb(0xB9B9BE));
    palette.setColor(QPalette::Inactive, QPalette::ButtonText, QRgb(0x9E9FA5));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QRgb(0x73747E));
    palette.setColor(QPalette::Active, QPalette::Highlight, QRgb(0x2D532D));
    palette.setColor(QPalette::Inactive, QPalette::Highlight, QRgb(0x354637));
    palette.setColor(QPalette::Disabled, QPalette::Highlight, QRgb(0x293D29));
    palette.setColor(QPalette::Active, QPalette::HighlightedText, QRgb(0xCCCCCC));
    palette.setColor(QPalette::Inactive, QPalette::HighlightedText, QRgb(0xCECECE));
    palette.setColor(QPalette::Disabled, QPalette::HighlightedText, QRgb(0x707070));
    palette.setColor(QPalette::All, QPalette::Light, QRgb(0x414145));
    palette.setColor(QPalette::All, QPalette::Midlight, QRgb(0x39393C));
    palette.setColor(QPalette::All, QPalette::Mid, QRgb(0x2F2F32));
    palette.setColor(QPalette::All, QPalette::Dark, QRgb(0x202022));
    palette.setColor(QPalette::All, QPalette::Shadow, QRgb(0x19191A));
    palette.setColor(QPalette::All, QPalette::Link, QRgb(0x68B668));
    palette.setColor(QPalette::Disabled, QPalette::Link, QRgb(0x74A474));
    palette.setColor(QPalette::All, QPalette::LinkVisited, QRgb(0x75B875));
    palette.setColor(QPalette::Disabled, QPalette::LinkVisited, QRgb(0x77A677));
    return palette;
}
"""

QSS = """\
QMenu {
    border: 1px solid #56565A;
}
QPushButton:!default:hover {
    background: #252528;
}
QPushButton:default:hover, QPushButton:checked:hover {
    background: #2E582E;
}
QToolTip {
    color: #BFBFBF;
    background-color: #2D532D;
}
"""


class PaletteCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        self.colors = self.root / "colors.toml"
        self.colors.write_text(THEME)
        self.src = self.root / "src"
        (self.src / "src/gui/styles/dark").mkdir(parents=True)
        self.cpp = self.src / "src/gui/styles/dark/DarkStyle.cpp"
        self.qss = self.src / "src/gui/styles/dark/darkstyle.qss"
        self.cpp.write_text(CPP)
        self.qss.write_text(QSS)

    def tearDown(self):
        self._tmp.cleanup()

    def run_script(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.colors), str(self.src), *extra],
            capture_output=True, text=True)

    # -- behaviour ---------------------------------------------------------

    def test_window_and_text_come_from_the_theme(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        cpp = self.cpp.read_text()
        self.assertIn("QPalette::Window, QRgb(0x000000)", cpp)
        self.assertIn("QPalette::WindowText, QRgb(0xFFD700)", cpp)
        self.assertIn("QPalette::Highlight, QRgb(0xFFCC00)", cpp)
        # The accent must not stay KeePassXC's green.
        self.assertNotIn("QRgb(0x2D532D)", cpp)

    def test_hardcoded_stylesheet_greys_follow_the_palette(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        qss = self.qss.read_text()
        self.assertIn("#ffcc00", qss)          # accent replaced the green
        self.assertNotIn("#2E582E", qss)
        self.assertNotIn("#56565A", qss)       # menu border took the theme muted colour

    def test_a_second_run_changes_nothing(self):
        self.run_script()
        once = (self.cpp.read_text(), self.qss.read_text())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.cpp.read_text(), self.qss.read_text()), once)

    def test_check_mode_reports_without_writing(self):
        before = (self.cpp.read_text(), self.qss.read_text())
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("would be rewritten", result.stdout)
        self.assertEqual((self.cpp.read_text(), self.qss.read_text()), before)

    # -- guard rails -------------------------------------------------------

    def test_refuses_a_source_tree_missing_the_dark_theme(self):
        self.qss.unlink()
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("not a KeePassXC source tree", result.stderr)

    def test_refuses_a_theme_without_the_core_keys(self):
        self.colors.write_text('mode = "dark"\nbackground = "#000000"\n')
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing foreground", result.stderr)

    def test_refuses_a_source_whose_palette_it_does_not_recognise(self):
        self.cpp.write_text("// nothing like the real file\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no QRgb() lines matched", result.stderr)


if __name__ == "__main__":
    unittest.main()
