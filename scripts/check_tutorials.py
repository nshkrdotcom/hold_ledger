#!/usr/bin/env python3
"""Execute the complete tutorial blocks and check their deliberate failures."""

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tmp/tutorial-checks'
WRAPPER = ['uv', 'run', '--locked', 'python', str(ROOT / 'scripts/local_run.py')]


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


def run(label, command, code=None, expected=0, fresh=False):
    environment = os.environ.copy()
    if fresh:
        environment.update(LYNX_CACHE='0', LYNX_DEBUG='lean')
    result = subprocess.run(
        WRAPPER + command, input=code, text=True, capture_output=True,
        cwd=ROOT, env=environment, timeout=300,
    )
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


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    crash = 'guides/formal_verification_crash_course.md'
    deeper = 'guides/reading_deeper_proofs.md'
    agentic = 'guides/agentic_verification.md'
    lean = standalone_lean_examples()
    for index, code in enumerate(lean):
        output = run(f'lean-{index}', ['lean', '--stdin'], code)
        if 'warning:' in output or 'error:' in output:
            raise RuntimeError(output)

    examples = [
        ('README.md', 's0 = Ledger.init('),
        (crash, 'sent ='),
        (crash, 'Ledger.request(s, 11, 300)'),
        (deeper, 'wrong_total ='),
        (deeper, 'Ledger.request(s, 11, 100)'),
        (agentic, 'early_release ='),
    ]
    for index, (guide, needle) in enumerate(examples):
        code = one(blocks(guide, 'elixir'), needle)
        path = save(f'example-{index}.exs', code)
        run(f'example-{index}', ['mix', 'run', path])

    for needle, language, source in [
        ('def valid?', 'elixir', 'lib/hold_ledger/spec.ex'),
        ('have compatible', 'lean', 'test/support/lean/Request.lean'),
        ('have find_eq', 'lean', 'test/support/lean/Request.lean'),
        ('have shaped', 'lean', 'test/support/lean/Lookup.lean'),
    ]:
        require((ROOT / source).read_text(), one(blocks(deeper, language), needle))

    base = one(blocks(crash, 'elixir'), 'defmodule CrashCourseTest')
    path = save('cap_test.exs', base)
    output = run('capacity-tests', ['mix', 'test', path, '--exclude', 'laws'])
    require(output, 'Result: 2 passed (1 property, 1 test), 1 excluded')
    output = run('capacity-proof', ['mix', 'test', path, '--only', 'laws'], fresh=True)
    require(output, 'Result: 1 passed, 2 excluded')
    require(output, 'fits/2')

    # Confirm a tactic failure on the unchanged claim, without claiming a bug.
    omega = re.sub(r'proof: ~LEAN""".*?"""', 'proof: ~LEAN"""\n      omega\n      """', base, count=1, flags=re.S)
    path = save('omega_test.exs', omega.replace('CrashCourseTest', 'CrashCourseOmegaTest'))
    output = run('omega-only', ['mix', 'test', path, '--only', 'laws'], expected=2, fresh=True)
    require(output, one(blocks(crash, 'text'), 'omega could not prove the goal'))

    mutant = base.replace('CrashCourseTest', 'CrashCourseMutantTest').replace(
        'if amount > remaining', 'if amount >= remaining')
    if mutant == base or 'if amount >= remaining' not in mutant:
        raise ValueError('Exact-fit mutation did not apply')
    path = save('cap_mutant_test.exs', mutant)
    output = run('mutant-tests', ['mix', 'test', path, '--exclude', 'laws', '--seed', '12345'], expected=2)
    require(output, 'Generated: 0')
    require(output, 'law fits/2 expects returned false')
    output = run('mutant-proof', ['mix', 'test', path, '--only', 'laws'], expected=2, fresh=True)
    require(output, one(blocks(crash, 'text'), 'unsolved goals'))

    # The complementary worked example extends the module, preserving its original claim.
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
    output = run('extended-tests', ['mix', 'test', path, '--exclude', 'laws'])
    require(output, 'Result: 4 passed (2 properties, 2 tests), 1 excluded')
    output = run('extended-proofs', ['mix', 'test', path, '--only', 'laws'], fresh=True)
    require(output, 'Result: 1 passed, 4 excluded')
    require(output, 'over_capacity/2')
    print('Tutorial examples and expected failures checked. Logs: tmp/tutorial-checks/')


if __name__ == '__main__':
    main()
