import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'stage_custom_packages', Path(__file__).with_name('stage-custom-packages.py'))
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)

# FormatPackages from OpenWrt v25.12.5, with ABI lookup stubbed locally.
FORMATTER = '''
GetABISuffix = $(if $(filter libgcc,$(1)),1)
define FormatPackages
$(strip $(foreach pkg,$(strip $(subst ",,$(1))),
  $(eval pkg_name:=$(firstword $(subst =, ,$(pkg))))
  $(if $(findstring =,$(pkg)),$(eval pkg_ver:==$(lastword $(subst =, ,$(pkg)))))
  $(pkg_name)$(call GetABISuffix,$(pkg_name))$(pkg_ver)
))
endef
all:
\t@echo '$(call FormatPackages,$(PACKAGES))'
'''


class ImageBuilderFormattingTest(unittest.TestCase):
    def test_pins_do_not_leak_into_following_packages(self):
        packages = ('purewrt=0.6.1-r1 luci ca-bundle '
                    'amneziawg-tools=3.1.20260812-r1 libgcc dnsmasq-full '
                    'libc=1.2.5-r5 kernel=6.12.94-r1 dropbear')
        with tempfile.TemporaryDirectory() as tmp:
            makefile = Path(tmp) / 'Makefile'
            makefile.write_text(FORMATTER)

            def format_packages():
                return subprocess.check_output(
                    ['make', '--no-print-directory', '-f', str(makefile),
                     f'PACKAGES={packages}'], text=True).strip()

            self.assertIn('libgcc1=3.1.20260812-r1', format_packages())
            stage.fix_imagebuilder_version_formatting(makefile)
            expected = packages.replace(' libgcc ', ' libgcc1 ')
            self.assertEqual(format_packages(), expected)
            stage.fix_imagebuilder_version_formatting(makefile)
            self.assertEqual(format_packages(), expected)

    def test_unknown_formatter_fails_for_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            makefile = Path(tmp) / 'Makefile'
            makefile.write_text('unknown formatter')
            with self.assertRaises(ValueError):
                stage.fix_imagebuilder_version_formatting(makefile)

    def test_all_purewrt_profiles_replace_dnsmasq(self):
        root = Path(__file__).resolve().parents[2]
        for packages in (root / 'devices').glob('*/packages.txt'):
            with self.subTest(device=packages.parent.name):
                lines = packages.read_text().splitlines()
                self.assertIn('-dnsmasq', lines)
                self.assertIn('dnsmasq-full', lines)
                self.assertNotIn('dnsmasq', lines)


if __name__ == '__main__':
    unittest.main()
