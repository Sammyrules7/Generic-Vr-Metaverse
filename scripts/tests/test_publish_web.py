"""Exercise publisher retention against s5cmd's listing format, without S3."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


PUBLISH = Path(__file__).resolve().parents[1] / 'publish_web.sh'
INCOMING = 'a' * 40
CURRENT = 'b' * 40
NEWEST = ['c' * 40, 'd' * 40, 'e' * 40]
OLD = 'f' * 40
PARTIAL = '9' * 40


class PublishTests(unittest.TestCase):
    def publish(self, completed, directories, pointer=CURRENT, listing_error=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            export = root / 'export'
            export.mkdir()
            (export / 'delivery-identity.txt').write_text('test identity\n')
            state = root / 'state.json'
            state.write_text(json.dumps(dict(completed=completed, directories=directories,
                                             pointer=pointer, listing_error=listing_error)))
            log = root / 'calls.jsonl'
            mock = root / 's5cmd'
            mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[3:]
with open(os.environ['MOCK_LOG'], 'a') as f: f.write(json.dumps(args) + '\\n')
state = json.loads(Path(os.environ['MOCK_STATE']).read_text())
command, key = args[:2]
if command == 'ls':
    if key.endswith('/builds/*/complete.txt'):
        if state['listing_error'] or not state['completed']: sys.exit(1)
        for index, sha in enumerate(state['completed']):
            print(f'2026/10/{28-index:02} 12:00:00 41 {sha}/complete.txt')
    elif key.endswith('/builds/'):
        for sha in state['directories']: print(f'DIR {sha}/')
    elif key.endswith('/commit.txt'):
        sys.exit(0 if state['pointer'] else 1)
    else: sys.exit(1)
elif command == 'cat': print(state['pointer'])
''')
            mock.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       MOCK_STATE=str(state), MOCK_LOG=str(log), GARAGE_BUCKET='test',
                       GARAGE_ENDPOINT='https://s3.invalid', BUILD_COMMIT=INCOMING,
                       EXPORT_DIR=str(export))
            result = subprocess.run(['bash', str(PUBLISH), 'branches/test'], env=env,
                                    text=True, capture_output=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def test_keep_pointer_incoming_and_three_newest(self):
        result, calls = self.publish(NEWEST + [CURRENT, OLD],
                                     [INCOMING, CURRENT, *NEWEST, OLD])
        self.assertEqual(result.returncode, 0, result.stderr)
        removed = [args[1] for args in calls if args[0] == 'rm']
        self.assertEqual(removed, [f's3://test/branches/test/builds/{OLD}/*'])

    def test_first_publication_without_completed_builds(self):
        result, calls = self.publish([], [], pointer='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(args[0] == 'sync' for args in calls))
        self.assertTrue(calls[-1][-1].endswith('/commit.txt'))

    def test_failed_listing_keeps_all_existing_builds(self):
        result, calls = self.publish(NEWEST, [CURRENT, *NEWEST, OLD], listing_error=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(args[0] == 'rm' for args in calls))

    def test_prunes_snapshot_without_complete_txt_ignores_other_rows(self):
        # A partial snapshot from a failed run has no complete.txt: it is not
        # among the completed listings, is not the incoming or pointer build,
        # and is pruned. s5cmd can also emit DIR rows for directories that are
        # not 40-hex build snapshots; those are neither kept nor pruned.
        result, calls = self.publish(
            NEWEST + [CURRENT],
            [INCOMING, CURRENT, *NEWEST, PARTIAL, 'short'])
        self.assertEqual(result.returncode, 0, result.stderr)
        removed = [args[1] for args in calls if args[0] == 'rm']
        self.assertEqual(removed, [f's3://test/branches/test/builds/{PARTIAL}/*'])


if __name__ == '__main__':
    unittest.main()
