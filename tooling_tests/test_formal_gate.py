import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('formal_gate', Path(__file__).resolve().parents[1] / 'scripts/formal_gate.py')
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class FormalGateTest(unittest.TestCase):
    def test_gate_matrix(self):
        self.assertTrue(gate.gate_passes('success', 'false', 'skipped'))
        self.assertTrue(gate.gate_passes('success', 'true', 'success'))
        for result in ['skipped', 'cancelled', 'failure', None, '']:
            self.assertFalse(gate.gate_passes('success', 'true', result))
        for detection in ['failure', 'cancelled', 'skipped', None]:
            self.assertFalse(gate.gate_passes(detection, 'false', 'success'))
        self.assertFalse(gate.gate_passes('success', '', 'success'))

    def test_relevant_paths(self):
        for path in ['lib/hold_ledger/server.ex', 'test/laws/po_s_test.exs',
                     'test/support/lean/Step.lean', 'scripts/formal_gate.py',
                     '.github/workflows/ci.yml', 'mix.lock', 'verification/laws.json']:
            self.assertTrue(gate.requires_formal([path]))
        self.assertFalse(gate.requires_formal(['guides/runtime.md', 'README.md']))

    def test_missing_base_and_diff_failure_require_formal(self):
        self.assertTrue(gate.detect('', 'HEAD'))
        self.assertTrue(gate.detect('0' * 40, 'HEAD'))
        with patch.object(gate.subprocess, 'run') as run:
            run.return_value.returncode = 1
            self.assertTrue(gate.detect('missing', 'HEAD'))
