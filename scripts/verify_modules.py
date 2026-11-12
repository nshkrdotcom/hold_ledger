#!/usr/bin/env python3
"""Dependency-ready isolated Lean module processes; stdout is Lynx protocol only."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from check_resources import GIB, resources
from check_runtime import cancel_running, tracked_process, worker_count
from check_scheduler import command_lease, delegate_parent, execution_scope, lease_command
from provision import local_env

ROOT = Path(__file__).resolve().parents[1]


def dependency_graph(nodes: list[dict]) -> dict[str, set[str]]:
    names = [node['module'] for node in nodes]
    if len(set(names)) != len(names):
        raise ValueError('Duplicate modules in verification plan')
    inventory = set(names)
    graph = {node['module']: set(node['imports']) & inventory for node in nodes}
    for node in nodes:
        unresolved = {name for name in node['imports'] if name.startswith(('Elixir.', 'HoldLedgerProof.'))} - inventory
        if unresolved:
            raise ValueError(f'Unsubmitted dependencies for {node["module"]}: {sorted(unresolved)}')
    visited, active = set(), set()
    def visit(name):
        if name in active:
            raise ValueError(f'Import cycle at {name}')
        if name in visited:
            return
        active.add(name)
        for parent in graph[name]:
            visit(parent)
        active.remove(name)
        visited.add(name)
    for name in graph:
        visit(name)
    return graph


def transitive_dependencies(graph, name):
    found = set()
    def visit(current):
        for parent in graph[current]:
            if parent not in found:
                found.add(parent)
                visit(parent)
    visit(name)
    return found


def invoke(argv, directory, label, *, env, request=None, cpu=1, memory=2 * GIB):
    with command_lease('lean:' + label, memory=memory, max_cpu=cpu) as lease:
        with (directory / (label + '.log')).open('ab') as log:
            process = subprocess.Popen(lease_command(argv, lease), cwd=ROOT, env=env,
                stdin=subprocess.PIPE if request is not None else subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=log, start_new_session=True)
            lease.started(process.pid)
            with tracked_process(process):
                output, _ = process.communicate(
                    (json.dumps(request) + '\n').encode() if request is not None else None, timeout=1800)
            log.write(output)
            if process.returncode != 0:
                raise RuntimeError(f'{label} exited {process.returncode}; see {log.name}')
            return output.decode()


def responses(output):
    result = []
    done = False
    for line in output.splitlines():
        record = json.loads(line)
        if record['status'] == 'failure':
            raise RuntimeError(record['message'])
        if record['status'] == 'done':
            done = True
        else:
            result.append(record)
    if not done:
        raise RuntimeError('Lean worker returned no completion record')
    return result


def verify(request: dict, project: Path, directory: Path) -> list[dict]:
    env = local_env()
    invoke(['lake', '--dir', str(project), 'build', 'Lynx/Lynx.Runner'], directory,
           'build', env=env, cpu=resources()['cpus'], memory=4 * GIB)
    search_path = invoke(['lake', '--dir', str(project), 'env', 'printenv', 'LEAN_PATH'],
                         directory, 'environment', env=env, memory=128 * 1024**2).strip()
    env['LEAN_PATH'] = search_path
    binary = project / '.lake/build/bin/Lynx-Runner'
    files = request['files']
    if not files:
        return []
    if request.get('export'):
        Path(request['export']).unlink(missing_ok=True)
    plan = responses(invoke([str(binary)], directory, 'plan', env=env,
                            request={'command': 'plan', 'version': '2.0', 'files': files}))
    if len(plan) != 1 or plan[0]['status'] != 'plan':
        raise RuntimeError('Missing exact module plan')
    graph = dependency_graph(plan[0]['nodes'])
    by_name = {file['module']: file for file in files}
    if set(by_name) != set(graph) or len(files) != len(by_name):
        raise RuntimeError('Verification request and plan inventories differ')
    (directory / 'plan.json').write_text(json.dumps(plan[0], indent=2) + '\n')
    artifacts, reports = {}, {}
    ids = {name: str(index) for index, name in enumerate(by_name)}
    jobs = worker_count(resources(), len(files), 2 * GIB)

    def node(name, inputs):
        staging = directory / ('staging-' + ids[name])
        published = directory / ('module-' + ids[name])
        worker_request = dict(request, command='verify', version='2.0',
                              files=[{k: v for k, v in by_name[name].items() if k != 'cache_key'}],
                              inventory=files, artifact_inputs=inputs, artifact_output=str(staging))
        worker_request.pop('export', None)
        records = responses(invoke([str(binary)], directory, 'node-' + ids[name],
                                   env=env, request=worker_request))
        if len(records) != 1 or records[0].get('module') != name:
            raise RuntimeError(f'Worker returned wrong module for {name}')
        report = records[0]
        clean = (report['status'] == 'ok' and report['cached'] is False
                 and all(d['severity'] not in ('error', 'warning') for d in report['diagnostics']))
        if clean:
            for extension in ('olean', 'olean.server', 'olean.private', 'ir.sig', 'ir'):
                if not (staging / ('module.' + extension)).is_file():
                    raise RuntimeError(f'Missing {extension} artifact for {name}')
            staging.rename(published)
        return report, str(published) if clean else None

    pending, active = set(graph), {}
    failed = False
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        while pending or active:
            for name in by_name:
                if name not in pending or len(active) >= jobs or failed:
                    continue
                if not graph[name] <= artifacts.keys():
                    continue
                closure = transitive_dependencies(graph, name)
                inputs = [{'module': parent, 'directory': artifacts[parent]}
                          for parent in by_name if parent in closure]
                active[pool.submit(node, name, inputs)] = name
                pending.remove(name)
            if not active:
                if pending and not failed:
                    raise RuntimeError(f'No runnable module in validated graph: {sorted(pending)}')
                break
            completed, _ = wait(active, return_when=FIRST_COMPLETED)
            for future in completed:
                name = active.pop(future)
                try:
                    report, artifact = future.result()
                except Exception as error:
                    report = {'status': 'error', 'module': name, 'file': by_name[name]['file'],
                              'time_ms': 0, 'cached': False, 'theorems': [],
                              'diagnostics': [{'severity': 'error', 'file': by_name[name]['file'],
                                  'module': name, 'declaration': None, 'message': str(error)}]}
                    artifact = None
                reports[name] = report
                if artifact:
                    artifacts[name] = artifact
                else:
                    if not failed:
                        cancel_running()
                    failed = True
                print(f'Lean modules completed {len(reports)}/{len(files)}: {name}', file=sys.stderr, flush=True)
    for name in pending:
        reports[name] = {'status': 'skipped', 'module': name, 'file': by_name[name]['file'],
                         'time_ms': 0, 'cached': False, 'theorems': [],
                         'diagnostics': [{'severity': 'error', 'file': by_name[name]['file'],
                            'module': name, 'declaration': None,
                            'message': 'Blocked by failed module; no export produced'}]}
    if request.get('export') and len(artifacts) == len(files):
        export = Path(request['export'])
        temporary = export.with_suffix(export.suffix + '.tmp')
        final = {'command': 'export', 'version': '2.0', 'export': str(temporary),
                 'artifact_inputs': [{'module': name, 'directory': artifacts[name]} for name in by_name]}
        responses(invoke([str(binary)], directory, 'export', env=env, request=final, memory=4 * GIB))
        if not temporary.is_file() or temporary.stat().st_size == 0:
            raise RuntimeError('Empty or missing final combined export')
        temporary.replace(export)
    result = [reports[name] for name in by_name]
    (directory / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main() -> int:
    try:
        request = json.loads(sys.stdin.readline())
        if request['version'] != '2.0' or request['command'] != 'verify':
            raise ValueError('Expected version 2.0 verification request')
        delegate_parent()
        # The coordinator enforces the original run ceiling after parent delegation.
        os.environ.pop('HOLD_LEDGER_CPU_BUDGET', None)
        root = ROOT / 'tmp/verification/modules'
        root.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='run-', dir=root))
        print(f'Lean module run: {directory}', file=sys.stderr, flush=True)
        with execution_scope(directory):
            for report in verify(request, Path(sys.argv[1]).resolve(), directory):
                print(json.dumps(report), flush=True)
        print(json.dumps({'status': 'done'}), flush=True)
        sys.stdin.read()  # Keep the Elixir port alive until its owner closes stdin.
        return 0
    except Exception as error:
        print(json.dumps({'status': 'failure', 'message': str(error)}), flush=True)
        sys.stdin.read()
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
