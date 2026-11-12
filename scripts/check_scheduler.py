"""Atomic resource admission shared by check task schedulers."""
from __future__ import annotations

from dataclasses import dataclass, replace
import threading
import time


@dataclass(frozen=True)
class Demand:
    cpu: int
    memory: int
    slots: int = 1
    pids: int = 1
    exclusive: tuple[str, ...] = ()

    def __post_init__(self):
        if min(self.cpu, self.slots, self.pids) < 1 or self.memory < 0:
            raise ValueError('positive CPU, slot and PID demands and nonnegative memory required')


class ResourcePool:
    """Single owner of CPU/memory/leaf/PID reservations and exclusive writers.

    An oversized memory task may run alone, explicitly recorded in its lease.
    Current headroom is incremental; it is never reduced again by active reservations.
    """
    def __init__(self, capacity: dict, jobs: int):
        if jobs < 1:
            raise ValueError('jobs must be positive')
        self.capacity = capacity
        self.jobs = min(jobs, capacity['cpus'])
        self.active: dict[str, dict] = {}
        self.condition = threading.Condition()
        self.cancelled = False

    def available(self) -> dict:
        with self.condition:
            return {'cpu': self.capacity['cpus'] - sum(x['demand'].cpu for x in self.active.values()),
                    'memory': self.capacity['memory_budget_bytes'] - sum(x['demand'].memory for x in self.active.values()),
                    'slots': self.jobs - sum(x['demand'].slots for x in self.active.values())}

    def try_acquire(self, task: str, demand: Demand, *, headroom: dict | None = None) -> dict | None:
        with self.condition:
            if self.cancelled:
                raise InterruptedError('Resource scheduling cancelled')
            if task in self.active:
                raise ValueError(f'Duplicate active task: {task}')
            free = self.available()
            if demand.cpu > free['cpu'] or demand.slots > free['slots']:
                return None
            keys = {key for lease in self.active.values() for key in lease['demand'].exclusive}
            if keys.intersection(demand.exclusive):
                return None
            memory_limit = free['memory']
            if headroom is not None:
                memory_limit = min(memory_limit, headroom['memory_budget_bytes'])
            oversized = demand.memory > memory_limit
            if oversized and self.active:
                return None
            pid_limit = (headroom or self.capacity).get('pid_headroom')
            # Live headroom already includes running processes; initial capacity does not.
            reserved_pids = 0 if headroom is not None else sum(x['demand'].pids for x in self.active.values())
            if pid_limit is not None and demand.pids + reserved_pids > pid_limit:
                return None
            used_ids = {cpu for lease in self.active.values() for cpu in lease['cpu_ids']}
            allowed = self.capacity.get('usable_cpus', list(range(self.capacity['cpus'])))
            cpu_ids = [cpu for cpu in allowed if cpu not in used_ids][:demand.cpu]
            lease = {'task': task, 'demand': demand, 'cpu_ids': cpu_ids, 'started': time.monotonic(),
                     'oversized_singleton': oversized}
            self.active[task] = lease
            return lease

    def release(self, task: str) -> None:
        with self.condition:
            if task not in self.active:
                raise ValueError(f'No active lease for {task}')
            del self.active[task]
            self.condition.notify_all()

    def cancel(self) -> None:
        with self.condition:
            self.cancelled = True
            self.condition.notify_all()

# Nested launchers keep one connection open for the lifetime of their leaf task.
# The top-level process owns the pool; no detached scheduling daemon is needed.
import contextlib
import functools
import fcntl
import math
import sys
import json
import os
from pathlib import Path
import socket
import socketserver
import tempfile
import uuid

from check_resources import resources


class Coordinator:
    def __init__(self, directory: Path, capacity: dict, jobs: int, parallelism: int = 1):
        self.pool = ResourcePool(capacity, jobs)
        self.parallelism = max(1, min(jobs, parallelism))
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True)
        self.events = (directory / 'leases.jsonl').open('a', buffering=1)
        self.events_lock = threading.Lock()
        self.waiters: list[str] = []
        self.queued_at = {}
        self.stop_monitor = threading.Event()
        self.profile = str((os.uname().nodename, capacity['cpus']))
        self.history_path = Path(__file__).resolve().parents[1] / '.local/checks/resource-estimates.json'
        try:
            self.history = json.loads(self.history_path.read_text()).get(self.profile, {})
        except (OSError, ValueError):
            self.history = {}
        self.observed = {}
        self.connections = set()
        self.socket_directory = tempfile.TemporaryDirectory(prefix='hold-ledger-leases-')
        self.path = str(Path(self.socket_directory.name) / 'coordinator.sock')
        owner = self

        class Handler(socketserver.StreamRequestHandler):
            def setup(self):
                super().setup()
                with owner.pool.condition:
                    owner.connections.add(self.connection)

            def finish(self):
                try:
                    super().finish()
                finally:
                    with owner.pool.condition:
                        owner.connections.discard(self.connection)

            def handle(self):
                task = None
                children = set()
                granted = False
                try:
                    data = json.loads(self.rfile.readline(65537))
                    if data.get('operation') == 'delegate':
                        parent = data['task']
                        with owner.pool.condition:
                            if parent in owner.pool.active:
                                owner.pool.release(parent)
                                owner.event('delegated', parent)
                        reply = {'delegated': True, 'cpus': owner.pool.capacity['cpus'],
                                 'cpu_ids': owner.pool.capacity.get('usable_cpus', [])[:owner.pool.capacity['cpus']]}
                        self.wfile.write((json.dumps(reply) + '\n').encode())
                        self.wfile.flush()
                        return
                    if data.get('operation') != 'acquire':
                        raise ValueError('Expected acquire')
                    task = data['task']
                    memory, maximum = int(data['memory']), int(data['max_cpu'])
                    pids = int(data.get('pids', 1))
                    exclusive = tuple(data.get('exclusive', []))
                    if maximum < 1 or memory < 0 or pids < 1:
                        raise ValueError('Invalid resource demand')
                    with owner.pool.condition:
                        owner.waiters.append(task)
                        owner.queued_at[task] = time.monotonic()
                    owner.event('queued', task, label=data.get('label'))
                    while True:
                        with owner.pool.condition:
                            if owner.pool.cancelled:
                                raise InterruptedError('Coordinator cancelled')
                            oldest = owner.waiters[0]
                            if oldest == task or time.monotonic() - owner.queued_at[oldest] < 30:
                                free = owner.pool.available()
                                # Reserve fair initial widths while independent stages are runnable.
                                width = max(1, math.ceil(owner.pool.capacity['cpus'] / owner.parallelism))
                                cpu = min(maximum, max(1, min(free['cpu'], width)))
                                profile_key = str(data.get('label')) + '@' + str(cpu)
                                estimate = owner.history.get(profile_key, {})
                                demand = Demand(cpu, max(memory, estimate.get('memory', 0)),
                                                pids=max(pids, estimate.get('pids', 1)), exclusive=exclusive)
                                headroom = resources()
                                used_cpu = owner.pool.capacity['cpus'] - free['cpu']
                                live_free = headroom['cpus'] - used_cpu
                                if live_free < demand.cpu:
                                    owner.pool.condition.wait(timeout=1)
                                    continue
                                lease = owner.pool.try_acquire(task, demand, headroom=headroom)
                                if lease:
                                    owner.waiters.remove(task)
                                    owner.queued_at.pop(task, None)
                                    lease['processes'] = children
                                    lease['profile_key'] = profile_key
                                    owner.pool.condition.notify_all()
                                    granted = True
                                    break
                            # A closed queued client cannot leave a permanent queue head.
                            readable, _, _ = __import__('select').select([self.connection], [], [], 0)
                            if readable and not self.connection.recv(1, socket.MSG_PEEK):
                                return
                            owner.pool.condition.wait(timeout=1)
                    owner.event('granted', task, cpu=cpu, memory=lease['demand'].memory, pids=lease['demand'].pids,
                                oversized_singleton=lease['oversized_singleton'])
                    self.wfile.write((json.dumps({'cpu': cpu, 'cpu_ids': lease['cpu_ids'], 'memory': lease['demand'].memory, 'task': task}) + '\n').encode())
                    self.wfile.flush()
                    while line := self.rfile.readline(65537):
                        message = json.loads(line)
                        if message['operation'] == 'started':
                            child = int(message['pid'])
                            with owner.pool.condition:
                                children.add(child)
                            owner.event('started', task, pid=child)
                        elif message['operation'] == 'release':
                            with owner.pool.condition:
                                children.clear()
                            return
                        else:
                            raise ValueError('Unknown lease operation')
                except (OSError, ValueError, KeyError, InterruptedError) as error:
                    owner.event('error', task, error=str(error))
                finally:
                    if children:
                        from check_runtime import stop_tree
                        for child in children:
                            stop_tree(child)
                    with owner.pool.condition:
                        if task in owner.waiters:
                            owner.waiters.remove(task)
                            owner.queued_at.pop(task, None)
                        if granted:
                            if task in owner.pool.active:
                                owner.pool.release(task)
                            owner.event('released', task, elapsed_seconds=time.monotonic() - lease['started'],
                                        peak_tree_rss_bytes=lease.get('peak_tree_rss_bytes'),
                                        sampled_cpu_seconds=lease.get('sampled_cpu_seconds'))
                        owner.pool.condition.notify_all()

        class Server(socketserver.ThreadingUnixStreamServer):
            daemon_threads = False
            block_on_close = True

        self.server = Server(self.path, Handler)
        os.chmod(self.path, 0o600)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.monitor = threading.Thread(target=self.observe, daemon=True)

    def observe(self):
        page = os.sysconf('SC_PAGE_SIZE')
        ticks = os.sysconf('SC_CLK_TCK')
        while not self.stop_monitor.wait(1):
            processes = {}
            for path in Path('/proc').glob('[0-9]*/stat'):
                try:
                    fields = path.read_text().rsplit(')', 1)[1].split()
                    processes[int(path.parent.name)] = (int(fields[1]),
                        int(fields[21]) * page, sum(int(fields[i]) for i in (11, 12, 13, 14)) / ticks,
                        int(fields[17]))
                except (OSError, ValueError, IndexError):
                    continue
            with self.pool.condition:
                for task, lease in self.pool.active.items():
                    members = set(lease.get('processes', ()))
                    while extra := {pid for pid, data in processes.items() if data[0] in members} - members:
                        members.update(extra)
                    samples = [processes[pid] for pid in members if pid in processes]
                    if not samples:
                        continue
                    rss = sum(data[1] for data in samples)
                    key = lease['profile_key']
                    bounds = self.observed.setdefault(key, {'memory': 0, 'pids': 0, 'sampled_cpu_seconds': 0})
                    bounds['memory'] = max(bounds['memory'], math.ceil(rss * 1.25))
                    bounds['pids'] = max(bounds['pids'], sum(data[3] for data in samples))
                    bounds['sampled_cpu_seconds'] = max(bounds['sampled_cpu_seconds'], sum(data[2] for data in samples))
                    lease['peak_tree_rss_bytes'] = max(lease.get('peak_tree_rss_bytes', 0), rss)
                    lease['sampled_cpu_seconds'] = max(lease.get('sampled_cpu_seconds', 0), sum(data[2] for data in samples))
                    demand = lease['demand']
                    if bounds['memory'] > demand.memory or bounds['pids'] > demand.pids:
                        lease['demand'] = replace(demand, memory=max(demand.memory, bounds['memory']),
                                                  pids=max(demand.pids, bounds['pids']))
                        self.event('reservation-increased', task, memory=lease['demand'].memory,
                                   pids=lease['demand'].pids, sampled_tree_rss_bytes=rss)
                self.pool.condition.notify_all()

    def save_observations(self):
        if not self.observed:
            return
        self.history_path.parent.mkdir(parents=True, exist_ok=True)
        with self.history_path.with_suffix('.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                history = json.loads(self.history_path.read_text())
            except (OSError, ValueError):
                history = {}
            profile = history.setdefault(self.profile, {})
            for key, observed in self.observed.items():
                entry = profile.setdefault(key, {})
                for field, value in observed.items():
                    entry[field] = max(entry.get(field, 0), value)
            pending = self.history_path.with_suffix('.tmp')
            pending.write_text(json.dumps(history, indent=2) + '\n')
            pending.replace(self.history_path)

    def event(self, state: str, task: str | None, **values):
        with self.events_lock:
            self.events.write(json.dumps({'state': state, 'task': task, 'time': time.time(), **values}) + '\n')

    def __enter__(self):
        self.thread.start()
        self.monitor.start()
        return self

    def __exit__(self, *_):
        self.stop_monitor.set()
        self.monitor.join()
        self.pool.cancel()
        self.server.shutdown()
        with self.pool.condition:
            connections = list(self.connections)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.server.server_close()
        self.thread.join()
        self.events.close()
        self.socket_directory.cleanup()
        self.save_observations()


@contextlib.contextmanager
def execution_scope(directory: Path | None = None, *, capacity: dict | None = None,
                    jobs: int | None = None, parallelism: int = 1):
    if os.environ.get('HOLD_LEDGER_COORDINATOR'):
        yield
        return
    capacity = capacity or resources()
    directory = directory or Path(tempfile.mkdtemp(prefix='execution-', dir=_execution_root()))
    with Coordinator(directory, capacity, jobs or capacity['default_jobs'], parallelism) as coordinator:
        os.environ['HOLD_LEDGER_COORDINATOR'] = coordinator.path
        try:
            yield coordinator
        finally:
            del os.environ['HOLD_LEDGER_COORDINATOR']


def _execution_root() -> Path:
    root = Path(__file__).resolve().parents[1] / 'tmp/execution'
    root.mkdir(parents=True, exist_ok=True)
    return root


def managed_run(function):
    @functools.wraps(function)
    def wrapped(*args, **kwargs):
        module = Path(function.__globals__.get('__file__', '')).stem
        parallelism = 1
        if module in ('run_mutants', 'mutation_campaign'):
            from check_runtime import worker_count, MUTANT_MEMORY_BYTES
            requested = None
            if '--jobs' in sys.argv:
                try:
                    requested = int(sys.argv[sys.argv.index('--jobs') + 1])
                except (ValueError, IndexError):
                    requested = 1
            tasks = 10 if module == 'run_mutants' else 100
            parallelism = worker_count(resources(), tasks, MUTANT_MEMORY_BYTES, requested)
        with execution_scope(parallelism=parallelism):
            return function(*args, **kwargs)
    return wrapped


class CommandLease:
    def __init__(self, connection, stream, allocation):
        self.connection, self.stream, self.allocation = connection, stream, allocation

    def started(self, pid: int):
        self.stream.write((json.dumps({'operation': 'started', 'pid': pid}) + '\n').encode())
        self.stream.flush()


@contextlib.contextmanager
def command_lease(label: str, *, memory: int, max_cpu: int = 1, pids: int = 1,
                  exclusive: tuple[str, ...] = ()):
    address = os.environ.get('HOLD_LEDGER_COORDINATOR')
    if not address:
        with execution_scope():
            with command_lease(label, memory=memory, max_cpu=max_cpu, pids=pids, exclusive=exclusive) as lease:
                yield lease
        return
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(address)
        with connection.makefile('rwb') as stream:
            stream.write((json.dumps({'operation': 'acquire', 'task': uuid.uuid4().hex,
                                      'label': label, 'memory': memory, 'max_cpu': max_cpu,
                                      'pids': pids, 'exclusive': exclusive}) + '\n').encode())
            stream.flush()
            line = stream.readline(65537)
            if not line:
                raise InterruptedError('Resource coordinator closed before granting lease')
            lease = CommandLease(connection, stream, json.loads(line))
            try:
                yield lease
            finally:
                try:
                    stream.write(b'{"operation":"release"}\n')
                    stream.flush()
                except (BrokenPipeError, ConnectionResetError):
                    raise InterruptedError('Resource coordinator lost during execution') from None


def delegates(argv: list[str]) -> bool:
    names = {'run_laws.py', 'run_mutants.py', 'mutation_campaign.py', 'check_tutorials.py',
             'run_differential.py', 'check_kernels_concurrent.py', 'run_browser.py', 'run_exunit.py'}
    return any(Path(arg).name in names for arg in argv) or ('-m' in argv and 'unittest' in argv)


def delegate_parent():
    """A compiler host surrenders its stage lease when its module driver takes over."""
    task = os.environ.pop('HOLD_LEDGER_PARENT_LEASE', None)
    address = os.environ.get('HOLD_LEDGER_COORDINATOR')
    if task and address:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(address)
            with connection.makefile('rwb') as stream:
                stream.write((json.dumps({'operation': 'delegate', 'task': task}) + '\n').encode())
                stream.flush()
                reply = stream.readline()
                if not reply:
                    raise InterruptedError('Coordinator lost while delegating parent lease')
                allocation = json.loads(reply)
                if allocation['cpu_ids']:
                    os.sched_setaffinity(0, set(allocation['cpu_ids']))
                os.environ['HOLD_LEDGER_CPU_BUDGET'] = str(allocation['cpus'])
                return True
    return False


def lease_command(argv, lease):
    """Contain all runtime threads to the CPUs reserved by this lease."""
    if lease is None:
        return argv
    return ['taskset', '--cpu-list', ','.join(str(cpu) for cpu in lease.allocation['cpu_ids']), *argv]
