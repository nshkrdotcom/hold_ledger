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
import check_resources as detection
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
            with patch.object(detection, 'Path', side_effect=fake_path), \
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

    def test_fractional_quota_and_cpuset_are_reported(self):
        result = self.detect({'/sys/fs/cgroup/parent/cpu.max': '150000 100000',
                              '/sys/fs/cgroup/parent/cpuset.cpus.effective': '2-3,7'})
        self.assertEqual(result['cpus'], 1)
        self.assertEqual(result['cpu_capacity'], 1.5)
        self.assertEqual(result['usable_cpus'], [2, 3, 7])

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

    def test_nested_clients_share_one_memory_and_slot_budget(self):
        from check_scheduler import Coordinator, command_lease
        first = threading.Event()
        release = threading.Event()
        second = threading.Event()
        errors = []
        capacity = {'cpus': 4, 'memory_budget_bytes': 8 * GIB}
        with tempfile.TemporaryDirectory() as folder, \
             patch('check_scheduler.resources', return_value=capacity), \
             patch('tempfile.tempdir', folder):
            with Coordinator(Path(folder), capacity, 4) as coordinator, \
                 patch.dict(os.environ, {'HOLD_LEDGER_COORDINATOR': coordinator.path}):
                def worker(label, started, wait=False):
                    try:
                        with command_lease(label, memory=6 * GIB):
                            started.set()
                            if wait:
                                release.wait(5)
                    except Exception as error:
                        errors.append(error)
                a = threading.Thread(target=worker, args=('first', first, True))
                b = threading.Thread(target=worker, args=('second', second))
                a.start()
                self.assertTrue(first.wait(5))
                b.start()
                try:
                    self.assertFalse(second.wait(.1))
                finally:
                    release.set()
                    a.join(5)
                    b.join(5)
                self.assertTrue(second.is_set())
                self.assertEqual(errors, [])

    def test_paired_task_minimum_survives_fair_sharing_and_one_cpu_hosts(self):
        from check_scheduler import Coordinator, command_lease
        for cpus, expected in ((4, 2), (1, 1)):
            capacity = {'cpus': cpus, 'memory_budget_bytes': 8 * GIB}
            with tempfile.TemporaryDirectory() as folder, \
                 patch('check_scheduler.resources', return_value=capacity):
                with Coordinator(Path(folder), capacity, cpus, parallelism=cpus) as coordinator, \
                     patch.dict(os.environ, {'HOLD_LEDGER_COORDINATOR': coordinator.path}):
                    with command_lease('paired', memory=GIB, min_cpu=2, max_cpu=2) as lease:
                        self.assertEqual(lease.allocation['cpu'], expected)
                        self.assertEqual(len(lease.allocation['cpu_ids']), expected)

    def test_compiler_parent_delegates_before_module_workers_request_resources(self):
        from check_scheduler import Coordinator, command_lease, delegate_parent
        capacity = {'cpus': 2, 'memory_budget_bytes': 4 * GIB}
        with tempfile.TemporaryDirectory() as folder, \
             patch('check_scheduler.resources', return_value=capacity):
            with Coordinator(Path(folder), capacity, 2) as coordinator, \
                 patch.dict(os.environ, {'HOLD_LEDGER_COORDINATOR': coordinator.path}):
                with command_lease('compiler', memory=4 * GIB, max_cpu=2,
                                   exclusive=('build',)) as parent:
                    with patch.dict(os.environ, {'HOLD_LEDGER_PARENT_LEASE': parent.allocation['task']}):
                        delegate_parent()
                    with command_lease('module', memory=2 * GIB, exclusive=('build',)):
                        pass

    def test_failed_full_never_dispatches_mutants(self):
        report = {'groups': {}}
        def group(name, *args):
            return {'state': 'failed' if name == 'full' else 'passed', 'workspace': '/fixture'}
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(suite, 'run_group', side_effect=group), \
             patch.object(suite, 'run_mutation_group') as mutants, \
             patch.object(suite, 'cancel_running'):
            with self.assertRaisesRegex(RuntimeError, 'Check group failed'):
                suite.schedule_groups('all', Path(folder), Path(folder),
                                      {'cpus': 24, 'memory_budget_bytes': 80 * GIB}, 24, report, lambda: None)
        mutants.assert_not_called()


class LeaseTests(unittest.TestCase):
    def test_atomic_admission_exclusive_writer_and_release(self):
        from check_scheduler import Demand, ResourcePool
        pool = ResourcePool({'cpus': 4, 'memory_budget_bytes': 8 * GIB}, 4)
        self.assertIsNotNone(pool.try_acquire('compile', Demand(2, 3 * GIB, exclusive=('build',))))
        self.assertIsNone(pool.try_acquire('docs', Demand(1, GIB, exclusive=('build',))))
        self.assertIsNone(pool.try_acquire('proof', Demand(3, GIB)))
        pool.release('compile')
        self.assertIsNotNone(pool.try_acquire('proof', Demand(4, 8 * GIB)))
        self.assertEqual(pool.available()['cpu'], 0)

    def test_live_memory_is_not_double_subtracted_and_pid_limit_blocks(self):
        from check_scheduler import Demand, ResourcePool
        pool = ResourcePool({'cpus': 4, 'memory_budget_bytes': 8 * GIB}, 4)
        pool.try_acquire('first', Demand(1, 3 * GIB))
        self.assertIsNotNone(pool.try_acquire('second', Demand(1, 4 * GIB),
                                            headroom={'memory_budget_bytes': 5 * GIB, 'pid_headroom': 3}))
        self.assertIsNone(pool.try_acquire('third', Demand(1, 0, pids=4),
                                         headroom={'memory_budget_bytes': GIB, 'pid_headroom': 3}))

    def test_oversized_task_is_explicit_and_alone(self):
        from check_scheduler import Demand, ResourcePool
        pool = ResourcePool({'cpus': 4, 'memory_budget_bytes': GIB}, 4)
        lease = pool.try_acquire('large', Demand(1, 2 * GIB))
        self.assertTrue(lease['oversized_singleton'])
        self.assertIsNone(pool.try_acquire('small', Demand(1, 1)))
        pool.release('large')
        pool.cancel()
        with self.assertRaises(InterruptedError):
            pool.try_acquire('cancelled', Demand(1, 1))
