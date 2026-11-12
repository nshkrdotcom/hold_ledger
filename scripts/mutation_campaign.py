#!/usr/bin/env python3
"""Finite operator campaign with executable properties before budgeted formal work.

Scores describe this operator universe, never specification completeness. Proof
script failure is inconclusive even when ordinary tests already found a witness.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

from check_runtime import resources, worker_count, MUTANT_MEMORY_BYTES

from run_mutants import ROOT, LEDGER, cmd, scratch_project
from run_laws import inspect_manifest
from check_scheduler import managed_run

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


def select_formal(records, budget):
    """Choose by manifest order, independent of parallel worker completion order."""
    return [record['id'] for record in records
            if record['classification'] == 'ordinary_survivor'][:budget]


@managed_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int)
    parser.add_argument('--limit', type=int, default=100)
    parser.add_argument('--formal-budget', type=int, default=1)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if args.limit <= 0 or args.formal_budget < 0 or args.timeout <= 0 or (args.jobs is not None and args.jobs < 1):
        parser.error('invalid campaign limits')
    output = ROOT / 'tmp/mutation-campaign'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'report.json').unlink(missing_ok=True)
    generation = cmd([sys.executable, str(ROOT / 'scripts/local_run.py'), 'mix', 'run',
                      'scripts/generate_mutations.exs', str(output)], ROOT,
                     timeout=args.timeout, log=output / 'generation.log')
    if generation['timeout'] or generation['exit'] != 0:
        raise RuntimeError('mutation candidate generation failed')
    candidates = json.loads((output / 'manifest.json').read_text())
    all_laws = [law['slug'] for law in inspect_manifest()]
    LAW_MAP['status'] = all_laws
    LAW_MAP['clause'] = all_laws
    original = (ROOT / LEDGER).read_bytes()
    jobs = worker_count(resources(), min(args.limit, len(candidates)), MUTANT_MEMORY_BYTES, args.jobs)
    report = {
              'universe': len(candidates), 'limit': args.limit, 'formal_budget': args.formal_budget,
              'law_map': LAW_MAP, 'jobs': jobs, 'results': []}
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
        control = cmd([sys.executable, str(project / 'scripts/local_run.py'),
                       'mix', 'format', str(LEDGER)], project, timeout=args.timeout,
                      log=output / 'equivalent-format.log')
        if control['timeout'] or control['exit'] != 0:
            raise RuntimeError('equivalent-edit formatting control failed')
        equivalent = cmd(command, project, timeout=args.timeout, log=output / 'equivalent-control.log')
        report['equivalent_edit_control'] = equivalent
        if equivalent['exit'] != 0:
            raise RuntimeError('equivalent source edit was incorrectly detected')
        def ordinary(site):
            candidate_dir = Path(folder) / site['id']
            candidate_dir.mkdir()
            candidate_project = scratch_project(candidate_dir)
            (candidate_project / LEDGER).write_bytes(Path(site['file']).read_bytes())
            command = [sys.executable, str(candidate_project / 'scripts/local_run.py'),
                       'mix', 'test', '--exclude', 'laws', '--seed', '12345']
            result = cmd(command, candidate_project, timeout=args.timeout,
                         log=output / f"{site['id']}.log")
            classification = classify_ordinary(result, (ROOT / result['log']).read_text())
            return dict(site, ordinary=result, targeted_laws=LAW_MAP[site['operator']],
                        classification=classification), candidate_project

        # map preserves manifest order even when completion order differs.
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            completed = list(pool.map(ordinary, candidates[:args.limit]))
        records = [record for record, _ in completed]
        selected = set(select_formal(records, args.formal_budget))

        def formal_attempt(item):
            record, candidate_project = item
            if record['classification'] != 'ordinary_survivor':
                return record
            if record['id'] not in selected:
                record['classification'] = 'unresolved_formal_budget'
                return record
            formal = [sys.executable, str(candidate_project / 'scripts/run_laws.py'),
                      '--stage', 'proofs', '--report', 'tmp/campaign-formal.json']
            for law in record['targeted_laws']:
                formal += ['--slug', law]
            record['formal'] = cmd(formal, candidate_project, timeout=args.timeout,
                                   log=output / f"{record['id']}-formal.log")
            record['classification'] = ('targeted_proofs_pass_full_suite_unchecked'
                                        if record['formal']['exit'] == 0 else
                                        'inconclusive_proof_automation')
            return record

        with ThreadPoolExecutor(max_workers=jobs) as pool:
            for record in pool.map(formal_attempt, completed):
                report['results'].append(record)
                pending = output / 'report.json.tmp'
                pending.write_text(json.dumps(report, indent=2) + '\n')
                pending.replace(output / 'report.json')
                print(f"{record['id']}: {record['classification']}", flush=True)
    if (ROOT / LEDGER).read_bytes() != original:
        raise RuntimeError('live reducer changed during campaign')
    report['not_run'] = [site['id'] for site in candidates[args.limit:]]
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
