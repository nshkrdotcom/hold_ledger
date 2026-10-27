"""No-execution provenance checks for Milestone B mutant harvest inputs."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from harvest_mutants import source_inputs
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


if __name__ == '__main__':
    unittest.main()
