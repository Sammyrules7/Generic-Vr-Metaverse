"""Run preview status and desktop download regressions in delivery CI."""
from pathlib import Path
import subprocess
import unittest


class PreviewDeliveryTests(unittest.TestCase):
    def test_delivery_contract(self):
        suite = Path(__file__).with_name('preview_delivery.test.mjs')
        result = subprocess.run(['node', '--test', str(suite)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
