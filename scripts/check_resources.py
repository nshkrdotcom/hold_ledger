"""Linux machine capacity and current headroom for all check launchers."""
from __future__ import annotations

import math
import os
from pathlib import Path
import resource
import shutil

GIB = 1024 ** 3


def read(path: Path) -> str | None:
    try:
        return path.read_text().strip()
    except OSError:
        return None


def cpu_set(value: str) -> set[int]:
    result = set()
    for item in value.split(','):
        if not item:
            continue
        ends = item.split('-')
        low, high = int(ends[0]), int(ends[-1])
        result.update(range(low, high + 1))
    return result


def positive_env(name: str, default: int) -> int:
    value = int(os.environ.get(name, default))
    if value < 1:
        raise ValueError(f'{name} must be positive')
    return value


def cgroup_paths() -> list[tuple[str, Path, Path]]:
    """Resolve actual controller mount roots, including cgroup namespaces."""
    memberships = []
    for line in (read(Path('/proc/self/cgroup')) or '').splitlines():
        _, controllers, relative = line.split(':', 2)
        memberships.append((set(controllers.split(',')) if controllers else set(), relative))
    mounts = []
    for line in (read(Path('/proc/self/mountinfo')) or '').splitlines():
        before, separator, after = line.partition(' - ')
        if not separator:
            continue
        fields, tail = before.split(), after.split()
        if tail[0] not in ('cgroup', 'cgroup2'):
            continue
        unescape = lambda s: s.replace('\\040', ' ').replace('\\134', '\\')
        mount_root, mountpoint = unescape(fields[3]), Path(unescape(fields[4]))
        controllers = set(tail[2].split(','))
        for member_controllers, relative in memberships:
            if tail[0] == 'cgroup2' and member_controllers:
                continue
            if tail[0] == 'cgroup' and not member_controllers & controllers:
                continue
            if mount_root == '/':
                suffix = relative.lstrip('/')
            elif relative == mount_root:
                suffix = ''
            elif relative.startswith(mount_root.rstrip('/') + '/'):
                suffix = relative[len(mount_root):].lstrip('/')
            elif relative == '/':
                suffix = ''  # namespace exposes the mount's subtree as its root
            else:
                continue
            current = mountpoint / suffix
            if not current.is_dir():
                current = mountpoint
            kind = 'v2' if tail[0] == 'cgroup2' else ','.join(sorted(member_controllers))
            mounts.append((kind, current, mountpoint))
    if not mounts:
        # Some restricted /proc mounts hide mountinfo but expose the unified tree.
        for controllers, relative in memberships:
            if not controllers:
                base = Path('/sys/fs/cgroup')
                current = base / relative.lstrip('/')
                mounts.append(('v2', current if current.is_dir() else base, base))
    return mounts


def resources() -> dict:
    affinity = set(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else set(range(os.cpu_count() or 1))
    usable = set(affinity)
    available = os.sysconf('SC_AVPHYS_PAGES') * os.sysconf('SC_PAGE_SIZE')
    meminfo = read(Path('/proc/meminfo'))
    if meminfo:
        fields = dict(line.split(':', 1) for line in meminfo.splitlines())
        available = int(fields['MemAvailable'].split()[0]) * 1024
    cpu_capacity = float(len(usable))
    pid_headroom = None
    constraints = []
    for kind, current, mountpoint in cgroup_paths():
        for directory in (current, *current.parents):
            if not directory.is_relative_to(mountpoint):
                break
            try:
                quota = read(directory / 'cpu.max') if kind == 'v2' else None
                if quota:
                    amount, period = quota.split()
                    if amount != 'max':
                        cpu_capacity = min(cpu_capacity, int(amount) / int(period))
                elif 'cpu' in kind.split(','):
                    amount = int(read(directory / 'cpu.cfs_quota_us') or -1)
                    period = int(read(directory / 'cpu.cfs_period_us') or 100000)
                    if amount > 0:
                        cpu_capacity = min(cpu_capacity, amount / period)
                cpuset = read(directory / ('cpuset.cpus.effective' if kind == 'v2' else 'cpuset.cpus'))
                if cpuset:
                    usable &= cpu_set(cpuset)
                memory = 'memory.max' if kind == 'v2' else 'memory.limit_in_bytes'
                usage = 'memory.current' if kind == 'v2' else 'memory.usage_in_bytes'
                limit, used = read(directory / memory), read(directory / usage)
                if limit and limit != 'max' and used is not None:
                    available = min(available, max(0, int(limit) - int(used)))
                limit, used = read(directory / 'pids.max'), read(directory / 'pids.current')
                if limit and limit != 'max' and used is not None:
                    remaining = max(0, int(limit) - int(used))
                    pid_headroom = remaining if pid_headroom is None else min(pid_headroom, remaining)
                constraints.append(str(directory))
            except (ValueError, ZeroDivisionError):
                # A malformed controller must not prevent other controllers/ancestors being read.
                continue
    cpu_capacity = min(cpu_capacity, len(usable), positive_env('HOLD_LEDGER_CPU_BUDGET', max(1, len(usable))))
    cpus = max(1, math.floor(cpu_capacity))
    memory_ceiling = os.environ.get('HOLD_LEDGER_MEMORY_BUDGET')
    reserve = max(2 * GIB, available // 10)
    budget = max(0, available - reserve)
    if memory_ceiling is not None:
        budget = min(budget, positive_env('HOLD_LEDGER_MEMORY_BUDGET', budget))
    disk = shutil.disk_usage(os.getcwd())
    return {'cpus': cpus, 'cpu_capacity': cpu_capacity, 'affinity_cpus': sorted(affinity),
            'usable_cpus': sorted(usable), 'available_memory_bytes': available,
            'memory_budget_bytes': budget, 'memory_reserve_bytes': reserve, 'default_jobs': cpus,
            'pid_headroom': pid_headroom, 'disk_free_bytes': disk.free,
            'fd_soft_limit': resource.getrlimit(resource.RLIMIT_NOFILE)[0],
            'cgroup_paths': constraints,
            'pressure': {kind: read(Path('/proc/pressure') / kind) for kind in ('cpu', 'memory', 'io')}}
