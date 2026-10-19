"""Run WebXR runtime regressions as part of delivery checks."""
from pathlib import Path
import subprocess
import unittest


class WebXRRuntimeTests(unittest.TestCase):
    def test_browser_input_recovery(self):
        test = Path(__file__).with_name('webxr_runtime.test.mjs')
        result = subprocess.run(['node', '--test', str(test)], text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
