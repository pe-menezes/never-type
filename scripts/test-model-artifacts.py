#!/usr/bin/env python3
"""Exercise setup recovery and model promotion in isolated temporary directories."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent


class ModelArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.root / 'home'))
        self.env.update(GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid')

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, code, *args):
        return subprocess.run(['bash', '-euo', 'pipefail', '-c',
                               'source "$1"; shift; ' + code, 'test',
                               str(SCRIPTS / 'model-artifacts.sh'), *map(str, args)],
                              env=self.env, capture_output=True, text=True)

    def git(self, *args):
        return subprocess.check_output(['git', *map(str, args)], env=self.env,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def test_receipt_rejects_truncation_and_same_size_corruption(self):
        model = self.root / 'model.bin'
        model.write_bytes(b'lmgg' + b'a' * 100)
        self.assertEqual(self.shell('model_write_receipt "$1"; model_has_receipt "$1"', model).returncode, 0)
        model.write_bytes(b'lmgg' + b'b' * 100)
        self.assertNotEqual(self.shell('model_has_receipt "$1"', model).returncode, 0)
        model.write_bytes(b'lmgg' + b'a' * 90)
        self.assertNotEqual(self.shell('model_has_receipt "$1"', model).returncode, 0)

    def test_unfinished_output_without_receipt_is_rejected(self):
        model = self.root / 'model.bin'
        model.write_bytes(b'lmgg' + b'a' * 100)
        self.assertNotEqual(self.shell('model_has_receipt "$1"', model).returncode, 0)
        Path(str(model) + '.sha256').write_text('not a checksum\n')
        self.assertNotEqual(self.shell('model_has_receipt "$1"', model).returncode, 0)

    def test_pinned_checkout_ignores_moving_remote_head_and_preserves_edits(self):
        origin = self.root / 'origin'
        self.git('init', '-q', origin)
        asset = origin / 'asset'
        asset.write_text('pinned')
        self.git('-C', origin, 'add', '.')
        self.git('-C', origin, 'commit', '-qm', 'First')
        pin = self.git('-C', origin, 'rev-parse', 'HEAD')
        asset.write_text('new upstream content')
        self.git('-C', origin, 'commit', '-qam', 'Second')
        checkout = self.root / 'checkout'
        result = self.shell('ensure_pinned_assets "$1" "$2" "$3"', checkout, origin, pin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((checkout / 'asset').read_text(), 'pinned')
        self.assertEqual(self.shell('ensure_pinned_assets "$1" "$2" "$3"', checkout, origin, pin).returncode, 0)
        (checkout / 'asset').write_text('local edit')
        self.assertNotEqual(self.shell('ensure_pinned_assets "$1" "$2" "$3"', checkout, origin, pin).returncode, 0)
        self.assertEqual((checkout / 'asset').read_text(), 'local edit')

    def test_existing_interpreter_repairs_failed_dependency_install(self):
        venv = self.root / 'venv'
        (venv / 'bin').mkdir(parents=True)
        interpreter = venv / 'bin/python'
        # Simulate an interpreter whose first pip attempt fails after venv creation.
        interpreter.write_text('''#!/bin/bash
root="$(dirname "$0")/.."
case "$*" in
  '-m ensurepip --upgrade') exit 0 ;;
  '-m pip install torch numpy')
    if [ ! -f "$root/attempted" ]; then touch "$root/attempted"; exit 1; fi
    touch "$root/ready"; exit 0 ;;
  *) test -f "$root/ready" ;;
esac
''')
        interpreter.chmod(0o755)
        self.assertNotEqual(self.shell('ensure_conversion_python "$1"', venv).returncode, 0)
        result = self.shell('ensure_conversion_python "$1"', venv)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((venv / 'ready').exists())

    def test_fetch_preserves_existing_model_on_failure_then_promotes_verified_copy(self):
        repo = self.root / 'repo'
        (repo / 'scripts').mkdir(parents=True)
        for filename in ('fetch-model.sh', 'model-artifacts.sh'):
            shutil.copy(SCRIPTS / filename, repo / 'scripts' / filename)
        models = repo / 'models'
        models.mkdir()
        name = 'ggml-large-v3-turbo-q5_0.bin'
        source = models / name
        source.write_bytes(b'lmgg' + b'a' * 100)
        self.assertEqual(self.shell('model_write_receipt "$1"', source).returncode, 0)
        destination = Path(self.env['HOME']) / 'Library/Application Support/NeverType/models' / name
        destination.parent.mkdir(parents=True)
        destination.write_bytes(b'previous installation')
        # Small fixtures exercise actual checksums and renames; stub only the size.
        bins = self.root / 'bin'
        bins.mkdir()
        stat = bins / 'stat'
        stat.write_text('#!/bin/bash\necho 524288000\n')
        stat.chmod(0o755)
        self.env['PATH'] = str(bins) + os.pathsep + self.env['PATH']
        source.write_bytes(b'lmgg' + b'b' * 100)
        command = ['bash', str(repo / 'scripts/fetch-model.sh')]
        result = subprocess.run(command, env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(destination.read_bytes(), b'previous installation')
        source.write_bytes(b'lmgg' + b'a' * 100)
        result = subprocess.run(command, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(destination.read_bytes(), source.read_bytes())
        self.assertEqual(self.shell('model_has_receipt "$1"', destination).returncode, 0)
        self.assertEqual(subprocess.run(command, env=self.env, capture_output=True).returncode, 0)

    def test_recording_accepts_five_minutes_and_rejects_invalid_durations(self):
        repo = self.root / 'recording'
        (repo / 'scripts').mkdir(parents=True)
        shutil.copy(SCRIPTS / 'record-fixture.sh', repo / 'scripts/record-fixture.sh')
        bins = self.root / 'bin'
        bins.mkdir()
        marker = self.root / 'ffmpeg-called'
        self.env['RECORD_TEST_MARKER'] = str(marker)
        for name, body in {
            'ffmpeg': 'touch "$RECORD_TEST_MARKER"; exit 7',
            'sleep': 'exit 0',
        }.items():
            path = bins / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        self.env['PATH'] = str(bins) + os.pathsep + self.env['PATH']
        command = ['bash', str(repo / 'scripts/record-fixture.sh'), 'long-speech']
        subprocess.run([*command, '300'], env=self.env, capture_output=True)
        self.assertTrue(marker.exists(), 'five minutes should reach the recorder')
        marker.unlink()
        for duration in ('2', '3601', 'abc', '3.5'):
            result = subprocess.run([*command, duration], env=self.env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists(), 'invalid durations must not acquire audio')


if __name__ == '__main__':
    unittest.main()
