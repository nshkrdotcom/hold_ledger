"""Resource detection, nested CPU allocation and dependency-aware dispatch."""
import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import check_runtime as runtime
import check_suite as suite

GIB = runtime.GIB


class ResourceTests(unittest.TestCase):
    def detect(self, files=None, affinity=24, inherited=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = {'/proc/meminfo': f'MemAvailable: {96 * 1024 * 1024} kB\n',
                    '/proc/self/cgroup': '0::/parent/leaf\n', **(files or {})}
            for name, value in data.items():
                path = root / name.lstrip('/')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
            (root / 'sys/fs/cgroup/parent/leaf').mkdir(parents=True, exist_ok=True)
            def fake_path(name):
                return root / str(name).lstrip('/')
            with patch.object(runtime, 'Path', side_effect=fake_path), \
                 patch.object(runtime.os, 'sched_getaffinity', return_value=set(range(affinity))), \
                 patch.object(runtime.os, 'sysconf', side_effect=lambda name: 4096 if name == 'SC_PAGE_SIZE' else 96 * GIB // 4096), \
                 patch.dict(os.environ, {} if inherited is None else {'HOLD_LEDGER_CPU_BUDGET': str(inherited)}, clear=True):
                return runtime.resources()

    def test_all_affinity_cpus_are_available_without_four_worker_or_half_cpu_cap(self):
        result = self.detect()
        self.assertEqual(result['cpus'], 24)
        self.assertEqual(result['default_jobs'], 24)
        self.assertLess(result['memory_budget_bytes'], result['available_memory_bytes'])
        self.assertEqual(self.detect(affinity=5)['default_jobs'], 5)

    def test_parent_cgroup_cpu_and_memory_limits_are_respected(self):
        result = self.detect({'/sys/fs/cgroup/parent/cpu.max': '250000 100000',
                              '/sys/fs/cgroup/parent/memory.max': str(20 * GIB),
                              '/sys/fs/cgroup/parent/memory.current': str(4 * GIB)})
        self.assertEqual(result['cpus'], 2)
        self.assertEqual(result['available_memory_bytes'], 16 * GIB)
        self.assertEqual(result['memory_budget_bytes'], 14 * GIB)

    def test_nested_cpu_budget_is_not_exceeded(self):
        self.assertEqual(self.detect(inherited=3)['cpus'], 3)

    def test_worker_count_respects_tasks_memory_and_explicit_ceiling(self):
        capacity = {'cpus': 24, 'memory_budget_bytes': 80 * GIB}
        self.assertEqual(runtime.worker_count(capacity, 10, 6 * GIB), 10)
        self.assertEqual(runtime.worker_count(capacity, 10, 6 * GIB, 2), 2)
        self.assertEqual(runtime.worker_count({**capacity, 'memory_budget_bytes': 19 * GIB}, 10, 6 * GIB), 3)
        self.assertEqual(runtime.worker_count({**capacity, 'memory_budget_bytes': 0}, 10, 6 * GIB), 1)

    def test_single_worker_uses_whole_cpu_budget_and_nested_workers_reallocate(self):
        with patch.object(runtime, 'resources', return_value={'cpus': 24}), patch.dict(os.environ, {}, clear=True):
            parent = runtime.worker_environment(1)
        self.assertIn('+S 24:24', parent['ERL_FLAGS'])
        with patch.object(runtime, 'resources', return_value={'cpus': 24}), patch.dict(os.environ, parent, clear=True):
            child = runtime.worker_environment(10, cpu_budget=20)
        self.assertIn('+S 2:2', child['ERL_FLAGS'])
        self.assertNotIn('+S 24:24', child['ERL_FLAGS'])
        self.assertEqual(child['HOLD_LEDGER_CPU_BUDGET'], '20')

    def test_explicit_scheduler_flags_survive_nested_allocation(self):
        with patch.object(runtime, 'resources', return_value={'cpus': 24}), \
             patch.dict(os.environ, {'ERL_FLAGS': '+S 2:2 +SDcpu 2 +A 8'}, clear=True):
            env = runtime.worker_environment(6)
        self.assertEqual(env['ERL_FLAGS'].count('+S '), 1)
        self.assertIn('+S 2:2 +SDcpu 2 +A 8', env['ERL_FLAGS'])


class SchedulerTests(unittest.TestCase):
    def test_mutants_start_after_full_before_unrelated_group_finishes(self):
        baseline_ready = threading.Event()
        mutants_started = threading.Event()
        report = {'groups': {}}
        observed = []
        def group(name, snapshot, run_dir, cpu):
            if name == 'full':
                baseline_ready.set()
            if name == 'web':
                self.assertTrue(mutants_started.wait(5), 'mutants waited for unrelated web completion')
            return {'state': 'passed', 'workspace': str(run_dir / 'workers' / name)}
        def mutants(snapshot, run_dir, jobs, cpu, baseline):
            self.assertTrue(baseline_ready.is_set())
            self.assertEqual(baseline, run_dir / 'workers/full')
            observed.append((jobs, cpu))
            mutants_started.set()
            return {'state': 'passed', 'workspace': str(baseline)}
        def save():
            allocations = [report['allocations'][name] for name in report.get('allocations', {})]
            self.assertTrue(all(a['cpu_budget'] >= a['workers'] for a in allocations))
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(suite, 'run_group', side_effect=group), \
             patch.object(suite, 'run_mutation_group', side_effect=mutants):
            root = Path(folder)
            suite.schedule_groups('all', root, root, {'cpus': 24, 'memory_budget_bytes': 80 * GIB}, 24, report, save)
        self.assertEqual(len(report['groups']), 8)
        self.assertTrue(observed)
        self.assertLessEqual(observed[0][0], 10)
        self.assertTrue(all(v['state'] == 'passed' for v in report['groups'].values()))

    def test_oversized_single_task_can_run_without_deadlock(self):
        active = 0
        peak = 0
        lock = threading.Lock()
        report = {'groups': {}}
        def group(name, *args):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            with lock:
                active -= 1
            return {'state': 'passed', 'workspace': '/fixture'}
        def save():
            pass
        with patch.object(suite, 'run_group', side_effect=group):
            suite.schedule_groups('web', Path('/fixture'), Path('/fixture'),
                                  {'cpus': 24, 'memory_budget_bytes': GIB}, 24, report, save)
        self.assertEqual(peak, 1)
        self.assertEqual(report['groups']['web']['state'], 'passed')

    def test_full_memory_reservation_blocks_other_groups_until_released(self):
        full_started = threading.Event()
        release_full = threading.Event()
        other_started = threading.Event()
        errors = []
        report = {'groups': {}}
        def group(name, *args):
            if name == 'full':
                full_started.set()
                if not release_full.wait(5):
                    raise RuntimeError('test did not release full')
            else:
                other_started.set()
            return {'state': 'passed', 'workspace': '/fixture'}
        def execute():
            try:
                suite.schedule_groups('all', Path('/fixture'), Path('/fixture'),
                                      {'cpus': 24, 'memory_budget_bytes': 12 * GIB},
                                      24, report, lambda: None)
            except Exception as error:
                errors.append(error)
        with patch.object(suite, 'run_group', side_effect=group), \
             patch.object(suite, 'run_mutation_group', return_value={'state': 'passed', 'workspace': '/fixture'}):
            thread = threading.Thread(target=execute)
            thread.start()
            try:
                self.assertTrue(full_started.wait(5))
                self.assertFalse(other_started.wait(.1))
                self.assertEqual(report['allocations']['full']['cpu_budget'], 24)
            finally:
                release_full.set()
                thread.join(5)
            self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(len(report['groups']), 8)

    def test_failed_full_never_dispatches_mutants(self):
        report = {'groups': {}}
        def group(name, *args):
            return {'state': 'failed' if name == 'full' else 'passed', 'workspace': '/fixture'}
        with patch.object(suite, 'run_group', side_effect=group), \
             patch.object(suite, 'run_mutation_group') as mutants, \
             patch.object(suite, 'cancel_running'):
            with self.assertRaisesRegex(RuntimeError, 'Check group failed'):
                suite.schedule_groups('all', Path('/fixture'), Path('/fixture'),
                                      {'cpus': 24, 'memory_budget_bytes': 80 * GIB}, 24, report, lambda: None)
        mutants.assert_not_called()
