"""Ensure native exports cannot silently fall back to a non-baking path."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

EXPORT = Path(__file__).resolve().parents[1] / 'export_with_shader_baking.sh'


class ShaderBakingExportTests(unittest.TestCase):
    def run_export(self, marker=True, status=0, extra=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'xvfb-run').write_text('#!/usr/bin/env bash\nshift 3\nexec "$@"\n')
            (root / 'godot').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ['CALL_LOG']).write_text(json.dumps(sys.argv[1:]))
if os.environ['BAKE_MARKER'] == '1':
    print('Storing File: res://.godot/shader_cache/SceneForwardMobileShaderRD/hash/test.vulkan.cache')
sys.exit(int(os.environ['EXIT_STATUS']))
''')
            for executable in ['xvfb-run', 'godot']:
                (root / executable).chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       CALL_LOG=str(root / 'call.json'), BAKE_MARKER=str(int(marker)),
                       EXIT_STATUS=str(status))
            arguments = extra or ['--path', 'project with spaces', '--export-release',
                                  'Android - Release', 'output with spaces.apk']
            result = subprocess.run(['bash', str(EXPORT), *arguments], env=env,
                                    text=True, capture_output=True)
            calls = json.loads((root / 'call.json').read_text()) if (root / 'call.json').exists() else []
            return result, calls

    def test_real_rendering_device_and_arguments_preserved(self):
        result, calls = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[:4], ['--display-driver', 'x11', '--rendering-driver', 'vulkan'])
        self.assertNotIn('--headless', calls)
        self.assertEqual(calls[-5:], ['--path', 'project with spaces', '--export-release',
                                    'Android - Release', 'output with spaces.apk'])

    def test_missing_baked_shaders_fails_export(self):
        result, _ = self.run_export(marker=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not include baked Vulkan shaders', result.stderr)

    def test_export_failure_is_not_hidden_by_logging(self):
        result, _ = self.run_export(status=7)
        self.assertEqual(result.returncode, 7)

    def test_headless_is_rejected(self):
        result, calls = self.run_export(extra=['--headless'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
