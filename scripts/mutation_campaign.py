#!/usr/bin/env python3
"""Finite operator campaign with executable properties before budgeted formal work.

Scores describe this operator universe, never specification completeness. Proof
script failure is inconclusive even when ordinary tests already found a witness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from run_mutants import ROOT, LEDGER, cmd, scratch_project
from run_laws import acceptance_sources, inspect_manifest

LAW_MAP = {
    '>': ['po_a1', 'po_a2', 'po_b1_processor_result', 'po_b1_void', 'po_b1_void_confirmed', 'po_c3'],
    '>=': ['po_a1', 'po_a2', 'po_c3'],
    '+': ['l3_accounting', 'l5_fresh', 'po_a1', 'po_s', 'po_c3'],
    '-': ['l3_accounting', 'po_a2', 'po_b1_processor_result', 'po_b1_void_confirmed', 'po_s', 'po_c3'],
    '==': ['l1_find', 'l2_identity', 'l4_structure', 'po_a4_duplicate', 'po_a4_conflict', 'po_c3'],
}


def classify_ordinary(result, text):
    if result['timeout']:
        return 'ordinary_timeout'
    if 'Compilation error' in text or '** (CompileError)' in text or '** (SyntaxError)' in text:
        return 'invalid_or_uncompilable'
    if result['exit'] == 2 and ('Assertion' in text or 'Expected truthy' in text or 'Expected false' in text or 'match (=)' in text):
        return 'executable_counterexample'
    if result['exit'] == 2 and 'code:' in text and any(
            name in text for name in ('** (FunctionClauseError)', '** (ArithmeticError)', '** (MatchError)', '** (CaseClauseError)')):
        return 'executable_exception_counterexample'
    if result['exit'] != 0:
        return 'ordinary_tool_failure'
    return 'ordinary_survivor'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--limit', type=int, default=100)
    parser.add_argument('--formal-budget', type=int, default=1)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if args.limit <= 0 or args.formal_budget < 0 or args.timeout <= 0:
        parser.error('invalid campaign limits')
    output = ROOT / 'tmp/mutation-campaign'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'report.json').unlink(missing_ok=True)
    subprocess.run([sys.executable, str(ROOT / 'scripts/local_run.py'), 'mix', 'run',
                    'scripts/generate_mutations.exs', str(output)], cwd=ROOT, check=True)
    candidates = json.loads((output / 'manifest.json').read_text())
    all_laws = [law['slug'] for law in inspect_manifest()]
    LAW_MAP['status'] = all_laws
    LAW_MAP['clause'] = all_laws
    original = (ROOT / LEDGER).read_bytes()
    input_paths = acceptance_sources() if args.formal_budget else sorted(
        set((ROOT / 'lib').rglob('*.ex')) | set((ROOT / 'test').rglob('*.ex')) |
        set((ROOT / 'test').rglob('*.exs')) |
        {ROOT / name for name in ('mix.exs', 'mix.lock', 'scripts/mutation_campaign.py',
         'scripts/generate_mutations.exs', 'scripts/run_mutants.py', 'scripts/local_run.py')})
    source_manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                       for path in input_paths}
    report = {'ledger_sha256': hashlib.sha256(original).hexdigest(),
              'source_sha256': source_manifest,
              'source_scope': 'formal and ordinary inputs' if args.formal_budget else 'ordinary executable inputs',

              'universe': len(candidates), 'limit': args.limit, 'formal_budget': args.formal_budget,
              'law_map': LAW_MAP, 'results': []}
    with tempfile.TemporaryDirectory(prefix='campaign-', dir=ROOT / 'tmp') as folder:
        project = scratch_project(Path(folder))
        command = [sys.executable, str(project / 'scripts/local_run.py'), 'mix', 'test', '--seed', '12345']
        baseline = cmd(command, project, timeout=args.timeout, log=output / 'baseline.log')
        report['baseline'] = baseline
        if baseline['exit'] != 0:
            raise RuntimeError('correct-source ordinary control failed')
        # A syntax-only reformat is an equivalent edit: it must remain a survivor.
        (project / LEDGER).write_bytes(original.replace(b'defmodule HoldLedger.Ledger do',
            b'defmodule HoldLedger.Ledger do\n  # Equivalent-edit negative control.', 1))
        control = subprocess.run([sys.executable, str(project / 'scripts/local_run.py'),
                                  'mix', 'format', str(LEDGER)], cwd=project,
                                 capture_output=True, text=True, check=False)
        if control.returncode != 0:
            raise RuntimeError('equivalent-edit formatting control failed')
        equivalent = cmd(command, project, timeout=args.timeout, log=output / 'equivalent-control.log')
        report['equivalent_edit_control'] = equivalent
        if equivalent['exit'] != 0:
            raise RuntimeError('equivalent source edit was incorrectly detected')
        budget = args.formal_budget
        for site in candidates[:args.limit]:
            (project / LEDGER).write_bytes(Path(site['file']).read_bytes())
            result = cmd(command, project, timeout=args.timeout, log=output / f"{site['id']}.log")
            text = (ROOT / result['log']).read_text()
            record = dict(site, ordinary=result, targeted_laws=LAW_MAP[site['operator']])
            classification = classify_ordinary(result, text)
            if classification != 'ordinary_survivor':
                record['classification'] = classification
            elif budget == 0:
                record['classification'] = 'unresolved_formal_budget'
            else:
                budget -= 1
                formal = [sys.executable, str(project / 'scripts/run_laws.py'), '--stage', 'proofs',
                          '--report', 'tmp/campaign-formal.json']
                for law in record['targeted_laws']:
                    formal += ['--slug', law]
                record['formal'] = cmd(formal, project, timeout=args.timeout,
                                       log=output / f"{site['id']}-formal.log")
                record['classification'] = ('targeted_proofs_pass_full_suite_unchecked'
                                            if record['formal']['exit'] == 0 else
                                            'inconclusive_proof_automation')
            report['results'].append(record)
            (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(f"{site['id']}: {record['classification']}", flush=True)
    if (ROOT / LEDGER).read_bytes() != original:
        raise RuntimeError('live reducer changed during campaign')
    if any(not (ROOT / name).is_file() or hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest
           for name, digest in source_manifest.items()):
        raise RuntimeError('Campaign inputs changed; result is not current-source evidence')
    report['source_unchanged'] = True
    report['not_run'] = [site['id'] for site in candidates[args.limit:]]
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
