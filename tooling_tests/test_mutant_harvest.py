"""No-execution provenance checks for Milestone B mutant harvest inputs."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from harvest_mutants import source_inputs, run_observation
from run_mutants import MUTANTS


class MutantHarvestStaticTest(unittest.TestCase):
    def test_all_ten_exact_witness_inputs_are_bound_to_the_original_tests(self):
        entries = source_inputs()
        self.assertEqual(set(entries), {m[0] for m in MUTANTS})
        self.assertEqual(len(entries), 10)
        for name, info in entries.items():
            source = ROOT / info['counterexample_path']
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), info['counterexample_sha256'])
            self.assertEqual(set(info['before']), {'amount_limit','hold_limit','used_amount','used_holds','entries'})
            self.assertIn(info['event']['type'], {'request','timeout','dispatch','void','retry','restart','processor_result','transport_ack'})
            self.assertIn('type', info['event'])

    def test_static_harvest_can_never_claim_observed_or_formal_pass(self):
        report = ROOT / 'tmp/verification/mutant-harvest-static-test.json'
        run = subprocess.run([sys.executable, str(ROOT / 'scripts/harvest_mutants.py'), '--report',
                              str(report.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        payload = json.loads(report.read_text())
        self.assertEqual(payload['mode'], 'STATIC_ONLY')
        self.assertEqual(payload['catcher_mapping'], 'NOT RUN')
        for item in payload['mutants'].values():
            self.assertEqual(item['provenance'], 'unexecuted')
            self.assertIsNone(item['output'])
            self.assertEqual(item['formal'], 'NOT RUN')
        report.unlink()


class MutantObservationFailureTest(unittest.TestCase):
    def test_failed_scratch_compilation_cannot_be_observed(self):
        with patch('harvest_mutants.cmd', return_value={'exit': 1, 'timeout': False}) as command:
            result = run_observation(ROOT, 'M1', 'unit-build-failure', 1)
        self.assertEqual(result['status'], 'unexecuted')
        self.assertNotIn('observation', result)
        self.assertEqual(command.call_count, 1)

    def test_successful_process_without_one_complete_marker_is_unexecuted(self):
        target = ROOT / 'tmp/verification/mutant-harvest-logs/M1-unit-invalid-marker.log'
        target.parent.mkdir(parents=True, exist_ok=True)
        for output in ['', 'MUTANT_OBSERVATION_JSON:{}\n', 'MUTANT_OBSERVATION_JSON:{invalid}\n']:
            target.write_text(output)
            with patch('harvest_mutants.cmd', return_value={'exit': 0, 'timeout': False}):
                result = run_observation(ROOT, 'M1', 'unit-invalid-marker', 1)
            self.assertEqual(result['status'], 'unexecuted')
            self.assertNotIn('observation', result)
        target.unlink()

    def test_compilation_timeout_stops_before_any_reducer_observation(self):
        with patch('harvest_mutants.cmd', return_value={'exit': None, 'timeout': True}) as command:
            result = run_observation(ROOT, 'M1', 'unit-build-timeout', 1)
        self.assertEqual(result['status'], 'unexecuted')
        self.assertNotIn('observation', result)
        self.assertEqual(command.call_count, 1)


if __name__ == '__main__':
    unittest.main()
