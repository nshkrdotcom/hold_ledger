"""Small executable checks of isolation, parallel dispatch and cancellation."""
import contextlib
import io
import json
import os
from pathlib import Path
import signal
import shlex
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import check_runtime
import check_suite


class CheckHelpersTest(unittest.TestCase):
    def test_source_copy_includes_dirty_and_untracked_files_and_private_dependencies(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'source'
            source.mkdir()
            def git(*args):
                subprocess.run(['git', *args], cwd=source, check=True, capture_output=True)
            git('init', '--quiet')
            (source / '.gitignore').write_text('deps/\n.local/\n.venv/\ntmp/\n')
            (source / 'tracked').write_text('committed')
            (source / 'deleted').write_text('remove me')
            git('add', '.')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                'commit', '--quiet', '-m', 'synthetic fixture')
            (source / 'tracked').write_text('uncommitted')
            (source / 'deleted').unlink()
            (source / 'untracked').write_text('new source')
            (source / 'deps').mkdir()
            (source / 'deps/cache').write_text('original')
            (source / '.local').mkdir()
            (source / '.venv').mkdir()
            copied = check_runtime.copy_project(source, root / 'copy')
            self.assertEqual((copied / 'tracked').read_text(), 'uncommitted')
            self.assertEqual((copied / 'untracked').read_text(), 'new source')
            self.assertFalse((copied / 'deleted').exists())
            self.assertTrue((copied / '.local').is_symlink())
            self.assertTrue((copied / '.venv').is_symlink())
            (copied / 'deps/cache').write_text('worker write')
            self.assertEqual((source / 'deps/cache').read_text(), 'original')
            # The master copies checkout -> snapshot -> worker. Shared symlinks
            # in the intermediate snapshot must not become source inputs.
            worker = check_runtime.copy_project(copied, root / 'worker')
            self.assertEqual((worker / '.venv').resolve(), source / '.venv')
            self.assertEqual((worker / '.local').resolve(), source / '.local')
            (worker / 'deps/cache').write_text('second worker write')
            self.assertEqual((copied / 'deps/cache').read_text(), 'worker write')

    def test_master_parallel_groups_and_full_baseline_reuse(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            barrier = threading.Barrier(2)
            active = 0
            peak = 0
            lock = threading.Lock()
            calls = []
            def group(name, snapshot, run_dir, jobs):
                nonlocal active, peak
                with lock:
                    active += 1
                    peak = max(peak, active)
                if name in ('quick', 'web'):
                    barrier.wait(timeout=3)
                with lock:
                    active -= 1
                workspace = run_dir / 'workers' / name
                workspace.mkdir(parents=True)
                return {'state': 'passed', 'workspace': str(workspace)}
            def copy(source, destination, **_options):
                destination.mkdir(parents=True)
                return destination
            def command(argv, *args, **kwargs):
                calls.append(argv)
                return 0
            capacity = dict(check_runtime.resources(), cpus=2, default_jobs=2)
            with patch.object(check_suite, 'resources', return_value=capacity), \
                 patch.object(check_suite, 'ROOT', root), \
                 patch.object(check_suite, 'copy_project', side_effect=copy), \
                 patch.object(check_suite, 'run_group', side_effect=group), \
                 patch.object(check_suite, 'command', side_effect=command), \
                 patch.object(sys, 'argv', ['check_suite.py', 'all', '--jobs', '2']), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(check_suite.main(), 0)
            self.assertEqual(peak, 2)
            self.assertIn('--baseline-report', calls[-1])
            self.assertEqual(calls[-1][-2], '--jobs')
            self.assertIn(int(calls[-1][-1]), (1, 2))
            report = json.loads(next(root.glob('tmp/check-runs/*/status.json')).read_text())
            self.assertEqual(report['state'], 'passed')
            self.assertEqual(len(report['groups']), 8)

    def test_cancellation_stops_a_descendant_in_its_own_session(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            marker = root / 'pids'
            child_code = (
                'import os,subprocess,sys,time; '
                'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"],start_new_session=True); '
                f'open({str(marker)!r},"w").write(str(os.getpid())+" "+str(p.pid)); '
                'time.sleep(60)')
            parent_code = (
                f'import sys; sys.path.insert(0,{str(Path(check_suite.__file__).parent)!r}); '
                'from pathlib import Path; from check_runtime import cancellation_scope; '
                'from check_suite import command; '
                f'\nwith cancellation_scope(): command([sys.executable,"-c",{child_code!r}],Path({str(root)!r}),"test",Path({str(root / "output.log")!r}),1)')
            parent = subprocess.Popen([sys.executable, '-c', parent_code], stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL, start_new_session=True)
            pids = []
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if marker.exists() and len(marker.read_text().split()) == 2:
                        pids = list(map(int, marker.read_text().split()))
                        break
                    time.sleep(.01)
                self.assertEqual(len(pids), 2)
                parent.send_signal(signal.SIGTERM)
                parent.wait(timeout=5)
                for pid in pids:
                    stat = Path(f'/proc/{pid}/stat')
                    self.assertTrue(not stat.exists() or stat.read_text().rsplit(')', 1)[1].split()[0] == 'Z')
            finally:
                if parent.poll() is None:
                    check_runtime.stop_tree(parent.pid)
                parent.wait()
                for pid in pids:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_bash_helpers_live_quiet_failure_and_arguments(self):
        scripts = Path(check_suite.__file__).parent
        with tempfile.TemporaryDirectory() as folder:
            stub = Path(folder) / 'uv'
            stub.write_text('#!/usr/bin/env bash\necho fixture-stdout\necho fixture-stderr >&2\n'
                            'if [[ "$1" == run ]]; then exit "${FIXTURE_EXIT:-0}"; fi\n')
            stub.chmod(0o755)
            env = dict(os.environ, PATH=folder + os.pathsep + os.environ['PATH'])
            for mode in ('quick', 'full', 'mutants', 'web', 'all'):
                script = scripts / f'check_{mode}.sh'
                for quiet in (False, True):
                    for code in (0, 23):
                        result = subprocess.run([str(script), '--jobs', '2'] + (['--quiet'] if quiet else []),
                                                cwd='/tmp', env=dict(env, FIXTURE_EXIT=str(code)),
                                                text=True, capture_output=True, timeout=5)
                        self.assertEqual(result.returncode, code, result.stderr)
                        log = Path(result.stderr.splitlines()[0].split(': ', 1)[1])
                        try:
                            self.assertIn('fixture-stdout', log.read_text())
                            self.assertIn('fixture-stderr', log.read_text())
                            self.assertEqual('fixture-stdout' in result.stdout, not quiet)
                        finally:
                            log.unlink()
                for args, code in ((['--help'], 0), (['--jobs', '0'], 2), (['--unknown'], 2)):
                    self.assertEqual(subprocess.run([str(script), *args], capture_output=True).returncode, code)

    def test_bash_termination_cleans_up_background_checks(self):
        script = Path(check_suite.__file__).parent / 'check_all.sh'
        with tempfile.TemporaryDirectory() as folder:
            temp = Path(folder)
            marker = temp / 'child'
            stub = temp / 'uv'
            stub.write_text('#!/usr/bin/env bash\nif [[ "$1" == sync ]]; then exit 0; fi\n'
                            f'exec {sys.executable} -c '+shlex.quote(
                                f'import os,time; open({str(marker)!r},"w").write(str(os.getpid())); time.sleep(60)')+'\n')
            stub.chmod(0o755)
            child = subprocess.Popen([str(script), '--quiet'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     env=dict(os.environ, PATH=folder + os.pathsep + os.environ['PATH']),
                                     start_new_session=True, text=True)
            log = None
            try:
                first = child.stderr.readline()
                log = Path(first.split(': ', 1)[1].strip())
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(marker.exists())
                pid = int(marker.read_text())
                child.terminate()
                child.communicate(timeout=5)
                self.assertEqual(child.returncode, 143)
                stat = Path(f'/proc/{pid}/stat')
                self.assertTrue(not stat.exists() or stat.read_text().rsplit(')', 1)[1].split()[0] == 'Z')
            finally:
                if child.poll() is None:
                    check_runtime.stop_tree(child.pid)
                child.communicate()
                if log:
                    log.unlink(missing_ok=True)

    def test_mutant_pool_runs_all_ten_and_retains_individual_errors(self):
        import run_mutants
        (run_mutants.ROOT / 'tmp').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=run_mutants.ROOT / 'tmp') as folder:
            report = Path(folder) / 'mutants.json'
            barrier = threading.Barrier(2)
            first = {entry[0] for entry in run_mutants.MUTANTS[:2]}
            seen = set()
            lock = threading.Lock()
            def mutant(entry, *args):
                with lock:
                    seen.add(entry[0])
                if entry[0] in first:
                    barrier.wait(timeout=3)
                if entry[0] == 'M10':
                    raise RuntimeError('fixture tool failure')
                return {'mutant_concrete': {'assertion_counterexample': True},
                        'formal_attribution': 'fixture'}
            with patch.object(sys, 'argv', ['run_mutants.py', '--execute', '--jobs', '2',
                                           '--baseline-report', 'unused', '--report', str(report)]), \
                 patch.object(run_mutants, 'inspect_manifest'), \
                 patch.object(run_mutants, 'accepted_baseline', return_value={}), \
                 patch.object(run_mutants, 'patch_correctly_applies', return_value='fixture'), \
                 patch.object(run_mutants, 'one_mutant', side_effect=mutant), \
                 patch.dict(os.environ), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_mutants.main(), 2)
            data = json.loads(report.read_text())
            self.assertEqual(seen, {entry[0] for entry in run_mutants.MUTANTS})
            self.assertFalse(data['all_concrete_detected'])
            self.assertEqual(data['mutants']['M10']['state'], 'INCOMPLETE')
            self.assertEqual(len(data['mutants']), 10)
