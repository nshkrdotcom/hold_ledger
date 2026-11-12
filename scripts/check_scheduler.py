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
