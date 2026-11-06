"""Resources, disposable source copies and child cleanup for local checks."""
from __future__ import annotations

from contextlib import contextmanager
import math
import hashlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import threading

GIB = 1024 ** 3
_children: set[int] = set()
_lock = threading.Lock()
_cancelled = threading.Event()


def resources() -> dict:
    cpus = len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else (os.cpu_count() or 1)
    available = os.sysconf('SC_AVPHYS_PAGES') * os.sysconf('SC_PAGE_SIZE')
    try:
        fields = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
        available = int(fields['MemAvailable'].split()[0]) * 1024
    except (OSError, KeyError, ValueError):
        pass
    # Consult the current cgroup and its ancestors, not the host CPU count alone.
    groups = Path('/sys/fs/cgroup')
    try:
        relative = next(line[3:] for line in Path('/proc/self/cgroup').read_text().splitlines()
                        if line.startswith('0::'))
        current = groups / relative.lstrip('/')
        if not current.is_dir():
            current = groups
        for directory in (current, *current.parents):
            if not directory.is_relative_to(groups):
                break
            cpu = directory / 'cpu.max'
            if cpu.is_file():
                quota, period = cpu.read_text().split()
                if quota != 'max':
                    cpus = min(cpus, max(1, math.floor(int(quota) / int(period))))
            memory = directory / 'memory.max'
            if memory.is_file() and (limit := memory.read_text().strip()) != 'max':
                used = int((directory / 'memory.current').read_text())
                available = min(available, max(0, int(limit) - used))
    except (OSError, StopIteration, ValueError):
        pass
    jobs = max(1, min(4, max(1, cpus // 2), available // (3 * GIB)))
    return {'cpus': cpus, 'available_memory_bytes': available, 'default_jobs': jobs}


def worker_environment(jobs: int, project: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    schedulers = max(1, min(4, resources()['cpus'] // jobs))
    flags = env.get('ERL_FLAGS', '')
    if '+S' not in flags.split():
        flags += f' +S {schedulers}:{schedulers}'
    if '+SDcpu' not in flags.split():
        flags += ' +SDcpu 1'
    if '+SDio' not in flags.split():
        flags += ' +SDio 1'
    env['ERL_FLAGS'] = flags.strip()
    env['PYTHONUNBUFFERED'] = '1'
    if project is not None:
        env['HOLD_LEDGER_CACHE_HOME'] = str(project / 'tmp/cache')
        # Workers use the already locked, prepared Python environment.
        env['UV_NO_SYNC'] = '1'
    return env


def source_files(source: Path) -> list[Path]:
    listed = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=source)
    return [Path(os.fsdecode(name)) for name in listed.split(b'\0') if name]


def source_manifest(source: Path) -> dict[str, str]:
    return {str(path): hashlib.sha256((source / path).read_bytes()).hexdigest()
            for path in source_files(source) if (source / path).is_file()}


def copy_directory(source: Path, destination: Path) -> None:
    if source.is_dir():
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Reflinks where supported; otherwise a real copy, never writable hardlinks.
        subprocess.run(['cp', '-a', '--reflink=auto', str(source), str(destination)], check=True)


def copy_project(source: Path, destination: Path, *, dependencies: bool = True) -> Path:
    subprocess.run(['git', 'clone', '--shared', '--quiet', str(source), str(destination)], check=True)
    # Git clone alone would silently omit uncommitted and untracked source changes.
    for relative in source_files(source):
        src, dst = source / relative, destination / relative
        if not src.exists() and not src.is_symlink():
            if dst.is_file() or dst.is_symlink():
                dst.unlink()
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.is_symlink():
            dst.unlink()
        if src.is_symlink():
            if dst.exists():
                dst.unlink()
            dst.symlink_to(os.readlink(src))
        else:
            shutil.copy2(src, dst)
    if dependencies:
        copy_directory(source / 'deps', destination / 'deps')
        copy_directory(source / 'apps/review_web/deps', destination / 'apps/review_web/deps')
    for name in ('.local', '.venv'):
        if (source / name).is_dir():
            (destination / name).symlink_to((source / name).resolve(), target_is_directory=True)
    return destination


def stop_tree(pid: int) -> None:
    """Include grandchildren that started their own process groups (Lean runners)."""
    parents = {}
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            parents[int(path.parent.name)] = int(path.read_text().rsplit(')', 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            pass
    descendants = {pid}
    while extra := {child for child, parent in parents.items() if parent in descendants} - descendants:
        descendants.update(extra)
    # A process group can survive its leader: kill it even if /proc/<pid> is gone.
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    for child in descendants:
        try:
            os.kill(child, signal.SIGKILL)
        except ProcessLookupError:
            pass


@contextmanager
def tracked_process(process: subprocess.Popen):
    with _lock:
        _children.add(process.pid)
        cancelled = _cancelled.is_set()
    try:
        if cancelled:
            stop_tree(process.pid)
            raise InterruptedError('Checks cancelled')
        yield process
    except BaseException:
        stop_tree(process.pid)
        process.wait()
        raise
    finally:
        if process.stdout is not None and process.poll() is not None:
            process.stdout.close()
        with _lock:
            _children.discard(process.pid)


@contextmanager
def cancellation_scope():
    _cancelled.clear()
    def cancel(signum, _frame):
        cancel_running()
        raise KeyboardInterrupt(f'Cancelled by signal {signum}')
    previous = {sig: signal.signal(sig, cancel) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def cancel_running() -> None:
    _cancelled.set()
    with _lock:
        children = list(_children)
    for pid in children:
        stop_tree(pid)
