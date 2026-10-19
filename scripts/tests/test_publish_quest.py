"""Run Node publisher regressions from the delivery CI test suite."""
from pathlib import Path
import subprocess
import unittest


class QuestPublisherTests(unittest.TestCase):
    def test_publishing_contract(self):
        suite = Path(__file__).with_name('publish_quest.test.mjs')
        result = subprocess.run(['node', '--test', str(suite)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
