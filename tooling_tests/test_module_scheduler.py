"""Generated graph validity and transitive artifact selection."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_modules import dependency_graph, transitive_dependencies


class ModuleGraphTests(unittest.TestCase):
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
