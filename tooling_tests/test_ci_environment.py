"""The composite setup must export its tools to later plain Mix steps."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CIEnvironmentTest(unittest.TestCase):
    def test_later_step_finds_repository_lake_without_local_run_wrapper(self):
        action = (ROOT / '.github/actions/setup-ledger/action.yml').read_text()
        step = re.search(
            r'    - name: Expose repository-local tools to later steps\n'
            r'      shell: bash\n      run: \|\n((?:        .*\n|\n)+)', action)
        self.assertIsNotNone(step, 'Setup must publish tools through GitHub environment files')
        script = textwrap.dedent(step.group(1))
        env = dict(os.environ)
        for name in ('ELAN_HOME', 'ELAN_TOOLCHAIN', 'XDG_CACHE_HOME'):
            env.pop(name, None)
        env['PATH'] = os.pathsep.join(
            part for part in env['PATH'].split(os.pathsep)
            if not Path(part).is_relative_to(ROOT / '.local'))

        with tempfile.TemporaryDirectory() as directory:
            path_file = Path(directory) / 'path'
            env_file = Path(directory) / 'env'
            env.update(GITHUB_PATH=str(path_file), GITHUB_ENV=str(env_file))
            subprocess.run(['bash', '-e', '-c', script], cwd=ROOT, env=env, check=True,
                           capture_output=True, text=True, timeout=30)
            env.update(line.split('=', 1) for line in env_file.read_text().splitlines())
            env['PATH'] = os.pathsep.join([*path_file.read_text().splitlines(), env['PATH']])
            self.assertEqual(shutil.which('lake', path=env['PATH']),
                             str(ROOT / '.local/elan/bin/lake'))
            self.assertEqual(env['ELAN_HOME'], str(ROOT / '.local/elan'))
            self.assertEqual(env['ELAN_TOOLCHAIN'], (ROOT / 'lean-toolchain').read_text().strip())
            result = subprocess.run(['lake', '--version'], cwd=ROOT, env=env,
                                    check=True, capture_output=True, text=True, timeout=30)
            self.assertIn('4.35.0', result.stdout)
