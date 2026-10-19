"""Run WebXR session lifecycle regressions as part of delivery checks."""
from pathlib import Path
import subprocess
import unittest


class WebXRBootstrapTests(unittest.TestCase):
    def test_browser_session_input_bootstrap(self):
        test = Path(__file__).with_name('webxr_session_bootstrap.test.cjs')
        result = subprocess.run(['node', '--test', str(test)], text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
