"""Generated graph validity and transitive artifact selection."""
from pathlib import Path
import sys
import subprocess
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_modules import dependency_graph, transitive_dependencies, lean_process_env, exchange_request, responses


class ModuleGraphTests(unittest.TestCase):
    def test_lean_threads_follow_cpu_lease_unless_operator_overrides(self):
        original = {'PATH': '/bin'}
        self.assertEqual(lean_process_env(original, 1)['LEAN_NUM_THREADS'], '1')
        self.assertEqual(lean_process_env(original, 4)['LEAN_NUM_THREADS'], '4')
        self.assertEqual(lean_process_env({'LEAN_NUM_THREADS': '2'}, 1)['LEAN_NUM_THREADS'], '2')
        self.assertNotIn('LEAN_NUM_THREADS', original)

    def test_diamond_keeps_shared_ancestor_in_transitive_inputs(self):
        graph = dependency_graph([
            {'module': 'Root', 'imports': ['Lean']},
            {'module': 'Left', 'imports': ['Root']},
            {'module': 'Right', 'imports': ['Root']},
            {'module': 'Law', 'imports': ['Left', 'Right']},
        ])
        self.assertEqual(transitive_dependencies(graph, 'Law'), {'Root', 'Left', 'Right'})
        self.assertEqual(graph['Law'], {'Left', 'Right'})

    def test_cycles_duplicates_and_missing_submitted_dependencies_fail(self):
        cases = [
            [{'module': 'A', 'imports': ['B']}, {'module': 'B', 'imports': ['A']}],
            [{'module': 'A', 'imports': []}, {'module': 'A', 'imports': []}],
            [{'module': 'Law', 'imports': ['HoldLedgerProof.Absent']}],
        ]
        for nodes in cases:
            with self.subTest(nodes=nodes), self.assertRaises(ValueError):
                dependency_graph(nodes)


class ModuleTransportTests(unittest.TestCase):
    def test_request_remains_open_until_chunked_completion_and_large_input(self):
        program = """
import json, os, select, sys
request = json.loads(sys.stdin.readline())
assert len(request['payload']) == 200000
if select.select([sys.stdin], [], [], .05)[0]:
    sys.exit(9)
os.write(1, b'{"status":"o')
os.write(1, b'k"}\\n{"status":"done"}\\n')
assert sys.stdin.read() == ''
"""
        with subprocess.Popen([sys.executable, '-c', program], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE) as child:
            output = exchange_request(child, {'payload': 'x' * 200000}, timeout=5)
            self.assertEqual(child.returncode, 0)
            self.assertEqual(responses(output.decode()), [{'status': 'ok'}])

    def test_early_exit_is_not_a_completed_request(self):
        with subprocess.Popen([sys.executable, '-c', 'import sys; sys.stdin.readline()'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE) as child:
            output = exchange_request(child, {}, timeout=5)
            with self.assertRaisesRegex(RuntimeError, 'no completion'):
                responses(output.decode())

    def test_silent_worker_keeps_finite_timeout_and_is_reaped(self):
        from check_runtime import tracked_process
        program = 'import sys; sys.stdin.readline(); sys.stdin.read()'
        with subprocess.Popen([sys.executable, '-c', program], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, start_new_session=True) as child:
            with self.assertRaises(subprocess.TimeoutExpired):
                with tracked_process(child):
                    exchange_request(child, {}, timeout=.1)
            self.assertIsNotNone(child.returncode)
