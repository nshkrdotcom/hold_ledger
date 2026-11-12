#!/usr/bin/env python3
"""Execute the complete tutorial blocks and check their deliberate failures."""

import os
import math
import sys
from pathlib import Path
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

from check_scheduler import command_lease, managed_run, lease_command
from check_resources import GIB, resources
from check_runtime import worker_environment, tracked_process, worker_count
from run_exunit import copy_test_build

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tmp/tutorial-checks'
WRAPPER = [sys.executable, str(ROOT / 'scripts/local_run.py')]
CPU_WIDTH = None


def blocks(path, language):
    return re.findall(r'```' + language + r'\n(.*?)```', (ROOT / path).read_text(), re.S)


def one(candidates, needle):
    matches = [code for code in candidates if needle in code]
    if len(matches) != 1:
        raise ValueError(f'Expected one block containing {needle!r}, found {len(matches)}')
    return matches[0]


def standalone_lean_examples():
    # Require each current worked example by identity, not a stale total.
    # New standalone blocks must also be registered so none silently go unchecked.
    inventory = {
        'guides/formal_verification_crash_course.md': (
            'theorem reserve_within_limit', 'theorem impossible_admission',
        ),
        'guides/reading_deeper_proofs.md': (
            'theorem exact_fit', 'theorem append_empty',
            'structure ToyHold', 'inductive ToyRun',
        ),
    }
    examples = []
    for guide, names in inventory.items():
        candidates = [code for code in blocks(guide, 'lean')
                      if code.lstrip().startswith(('import Lean', 'structure ToyHold'))]
        selected = [one(candidates, name) for name in names]
        if len(selected) != len(candidates):
            raise ValueError(f'Unregistered standalone Lean example in {guide}')
        examples.extend(selected)
    return examples


def normalize(value):
    return '\n'.join(line.strip() for line in value.strip().splitlines())


def execute(argv, *, code, env, log, timeout, lease):
    with log.open('wb') as output:
        process = subprocess.Popen(lease_command(argv, lease), cwd=ROOT, env=env,
            stdin=subprocess.PIPE if code is not None else subprocess.DEVNULL,
            stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        lease.started(process.pid)
        with tracked_process(process):
            process.communicate(code.encode() if code is not None else None, timeout=timeout)
    return subprocess.CompletedProcess(argv, process.returncode, log.read_text(), '')


def run(label, command, code=None, expected=0, fresh=False):
    with command_lease('tutorial:' + label, memory=3 * GIB, max_cpu=CPU_WIDTH or resources()['cpus'],
                       exclusive=(str(ROOT / '_build'),) if label.startswith('prepare-') else ()) as lease:
        environment = worker_environment(1, cpu_budget=lease.allocation['cpu'])
        environment['HOLD_LEDGER_PARENT_LEASE'] = lease.allocation['task']
        if 'mix' in command and not label.startswith('prepare-'):
            parent = OUTPUT / 'builds'
            parent.mkdir(exist_ok=True)
            build = Path(tempfile.mkdtemp(prefix=label + '-', dir=parent)) / 'build'
            copy_test_build(ROOT, build)
            environment['MIX_BUILD_PATH'] = str(build)
            environment['MIX_ENV'] = 'test'
            index = command.index('mix') + 2
            command = command[:index] + ['--no-compile', '--no-deps-check'] + command[index:]
        if fresh:
            environment.update(LYNX_CACHE='0', LYNX_DEBUG='lean')
        result = execute(WRAPPER + command, code=code, env=environment,
                         log=OUTPUT / f'{label}.log', timeout=300, lease=lease)
    output = result.stdout + result.stderr
    (OUTPUT / f'{label}.log').write_text(output)
    if result.returncode != expected:
        raise RuntimeError(f'{label}: expected exit {expected}, got {result.returncode}\n{output}')
    print(f'{label}: expected exit {expected}', flush=True)
    return output


def require(output, text):
    if normalize(text) not in normalize(output):
        raise RuntimeError(f'Missing expected evidence: {text}')


def save(name, code):
    path = OUTPUT / name
    path.write_text(code)
    return str(path.relative_to(ROOT))


@managed_run
def main():
    global OUTPUT, CPU_WIDTH
    OUTPUT.mkdir(parents=True, exist_ok=True)
    OUTPUT = Path(tempfile.mkdtemp(prefix='run-', dir=OUTPUT))
    crash = 'guides/formal_verification_crash_course.md'
    deeper = 'guides/reading_deeper_proofs.md'
    agentic = 'guides/agentic_verification.md'
    tasks = []
    for index, code in enumerate(standalone_lean_examples()):
        tasks.append((f'lean-{index}', ['lean', '--stdin'], code, 0, False, []))
    examples = [('README.md', 's0 = Ledger.init('), (crash, 'sent ='),
                (crash, 'Ledger.request(s, 11, 300)'), (deeper, 'wrong_total ='),
                (deeper, 'Ledger.request(s, 11, 100)'), (agentic, 'early_release =')]
    for index, (guide, needle) in enumerate(examples):
        path = save(f'example-{index}.exs', one(blocks(guide, 'elixir'), needle))
        tasks.append((f'example-{index}', ['mix', 'run', path], None, 0, False, []))
    for needle, language, source in [
        ('def valid?', 'elixir', 'lib/hold_ledger/spec.ex'),
        ('have compatible', 'lean', 'test/support/lean/Request.lean'),
        ('have find_eq', 'lean', 'test/support/lean/Request.lean'),
        ('have shaped', 'lean', 'test/support/lean/Lookup.lean'),
    ]:
        require((ROOT / source).read_text(), one(blocks(deeper, language), needle))

    base = one(blocks(crash, 'elixir'), 'defmodule CrashCourseTest')
    path = save('cap_test.exs', base)
    tasks.extend([
        ('capacity-tests', ['mix', 'test', path, '--exclude', 'laws'], None, 0, False,
         ['Result: 2 passed (1 property, 1 test), 1 excluded']),
        ('capacity-proof', ['mix', 'test', path, '--only', 'laws'], None, 0, True,
         ['Result: 1 passed, 2 excluded', 'fits/2']),
    ])
    omega = re.sub(r'proof: ~LEAN""".*?"""', 'proof: ~LEAN"""\n      omega\n      """', base, count=1, flags=re.S)
    path = save('omega_test.exs', omega.replace('CrashCourseTest', 'CrashCourseOmegaTest'))
    tasks.append(('omega-only', ['mix', 'test', path, '--only', 'laws'], None, 2, True,
                  [one(blocks(crash, 'text'), 'omega could not prove the goal')]))
    mutant = base.replace('CrashCourseTest', 'CrashCourseMutantTest').replace('if amount > remaining', 'if amount >= remaining')
    if mutant == base or 'if amount >= remaining' not in mutant:
        raise ValueError('Exact-fit mutation did not apply')
    path = save('cap_mutant_test.exs', mutant)
    tasks.extend([
        ('mutant-tests', ['mix', 'test', path, '--exclude', 'laws', '--seed', '12345'], None, 2, False,
         ['Generated: 0', 'law fits/2 expects returned false']),
        ('mutant-proof', ['mix', 'test', path, '--only', 'laws'], None, 2, True,
         [one(blocks(crash, 'text'), 'unsolved goals')]),
    ])
    law = one(blocks(crash, 'elixir'), 'law(over_capacity(')
    extended = base.rsplit('  end', 1)
    code = extended[0] + '\n' + law + '\n  end' + extended[1]
    code = code.replace('  laws "capacity" do', '''  test "over-capacity witness" do
    assert over_capacity(2, 1)
  end

  property "over-capacity generated pairs" do
    check all(remaining <- integer(), gap <- positive_integer()) do
      assert over_capacity(remaining + gap, remaining)
    end
  end

  laws "capacity" do''')
    path = save('extended_test.exs', code)
    tasks.extend([
        ('extended-tests', ['mix', 'test', path, '--exclude', 'laws'], None, 0, False,
         ['Result: 4 passed (2 properties, 2 tests), 1 excluded']),
        ('extended-proofs', ['mix', 'test', path, '--only', 'laws'], None, 0, True,
         ['Result: 1 passed, 4 excluded', 'over_capacity/2']),
    ])
    run('prepare-dev', ['mix', 'compile', '--warnings-as-errors'])
    run('prepare-test', ['env', 'MIX_ENV=test', 'mix', 'compile', '--warnings-as-errors'])
    def check(task):
        label, command, code, expected, fresh, evidence = task
        output = run(label, command, code, expected, fresh)
        if label.startswith('lean-') and ('warning:' in output or 'error:' in output):
            raise RuntimeError(output)
        for text in evidence:
            require(output, text)
    jobs = worker_count(resources(), len(tasks), 3 * GIB)
    CPU_WIDTH = max(1, math.ceil(resources()['cpus'] / jobs))
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        list(pool.map(check, tasks))
    print(f'Tutorial examples and expected failures checked. Logs: {OUTPUT}')


if __name__ == '__main__':
    main()
