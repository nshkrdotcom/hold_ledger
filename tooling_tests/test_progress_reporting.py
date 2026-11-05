import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

import run_laws


class ProgressTests(unittest.TestCase):
    def test_output_is_visible_before_command_finishes(self):
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / 'tmp') as folder:
            folder = Path(folder)
            release = folder / 'release'
            log = folder / 'live.log'
            output = io.StringIO()
            result = []
            code = ('import pathlib,time; print("live marker", flush=True); '
                    f'p=pathlib.Path({str(release)!r}); '
                    '\nwhile not p.exists(): time.sleep(0.01)\n')
            def worker():
                result.append(run_laws.run([sys.executable, '-c', code],
                    cwd=run_laws.ROOT, env=None, log=log, timeout=5))
            with contextlib.redirect_stdout(output):
                thread = threading.Thread(target=worker)
                thread.start()
                try:
                    deadline = time.monotonic() + 3
                    while 'live marker' not in output.getvalue() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertIn('live marker', output.getvalue())
                    self.assertIn('live marker', log.read_text())
                    self.assertTrue(thread.is_alive())
                finally:
                    release.touch()
                    thread.join(timeout=6)
            self.assertFalse(thread.is_alive())
            self.assertEqual(result[0]['exit'], 0)
            self.assertFalse(result[0]['timeout'])

    def test_nonzero_exit_and_timeout_remain_failures(self):
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / 'tmp') as folder:
            for code, timeout, expected in [
                ('import sys; print("failure"); sys.exit(7)', 5, 7),
                ('import os,time; os.close(1); os.close(2); time.sleep(30)', 1, None),
                ('import subprocess,sys,time; subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); print("started",flush=True); time.sleep(30)', 1, None),
            ]:
                log = Path(folder) / 'command.log'
                with contextlib.redirect_stdout(io.StringIO()):
                    result = run_laws.run([sys.executable, '-c', code],
                        cwd=run_laws.ROOT, env=None, log=log, timeout=timeout)
                self.assertEqual(result['exit'], expected)
                self.assertEqual(result['timeout'], expected is None)
                self.assertLess(result['wall_seconds'], 6)
                if "os.close" not in code:
                    self.assertTrue(log.read_text())

    def test_silent_command_reports_elapsed_time(self):
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / 'tmp') as folder:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = run_laws.run([sys.executable, '-c', 'import time; time.sleep(16)'],
                    cwd=run_laws.ROOT, env=None, log=Path(folder)/'silent.log', timeout=25)
            self.assertEqual(result['exit'], 0)
            self.assertIn('Still running: 15s elapsed', output.getvalue())
