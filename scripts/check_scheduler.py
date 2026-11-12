"""Atomic resource admission shared by check task schedulers."""
from __future__ import annotations

from dataclasses import dataclass
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
            lease = {'task': task, 'demand': demand, 'started': time.monotonic(),
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
                    owner.event('queued', task, label=data.get('label'))
                    while True:
                        with owner.pool.condition:
                            if owner.pool.cancelled:
                                raise InterruptedError('Coordinator cancelled')
                            if owner.waiters[0] == task:
                                free = owner.pool.available()
                                # Reserve fair initial widths while independent stages are runnable.
                                width = max(1, owner.pool.capacity['cpus'] // owner.parallelism)
                                cpu = min(maximum, max(1, min(free['cpu'], width)))
                                demand = Demand(cpu, memory, pids=pids, exclusive=exclusive)
                                headroom = resources()
                                used_cpu = owner.pool.capacity['cpus'] - free['cpu']
                                live_free = headroom['cpus'] - used_cpu
                                if live_free < demand.cpu:
                                    owner.pool.condition.wait(timeout=1)
                                    continue
                                lease = owner.pool.try_acquire(task, demand, headroom=headroom)
                                if lease:
                                    owner.waiters.pop(0)
                                    owner.pool.condition.notify_all()
                                    granted = True
                                    break
                            # A closed queued client cannot leave a permanent queue head.
                            readable, _, _ = __import__('select').select([self.connection], [], [], 0)
                            if readable and not self.connection.recv(1, socket.MSG_PEEK):
                                return
                            owner.pool.condition.wait(timeout=1)
                    owner.event('granted', task, cpu=cpu, memory=memory,
                                oversized_singleton=lease['oversized_singleton'])
                    self.wfile.write((json.dumps({'cpu': cpu, 'memory': memory}) + '\n').encode())
                    self.wfile.flush()
                    while line := self.rfile.readline(65537):
                        message = json.loads(line)
                        if message['operation'] == 'started':
                            child = int(message['pid'])
                            children.add(child)
                            owner.event('started', task, pid=child)
                        elif message['operation'] == 'release':
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
                        if granted:
                            owner.pool.release(task)
                            owner.event('released', task)
                        owner.pool.condition.notify_all()

        class Server(socketserver.ThreadingUnixStreamServer):
            daemon_threads = False
            block_on_close = True

        self.server = Server(self.path, Handler)
        os.chmod(self.path, 0o600)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def event(self, state: str, task: str | None, **values):
        with self.events_lock:
            self.events.write(json.dumps({'state': state, 'task': task, 'time': time.time(), **values}) + '\n')

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
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
        parallelism = 10 if module in ('run_mutants', 'mutation_campaign') else 1
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
             'run_differential.py', 'check_kernels_concurrent.py', 'run_browser.py'}
    return any(Path(arg).name in names for arg in argv) or ('-m' in argv and 'unittest' in argv)
