#!/usr/bin/env python3
"""Sandboxed pinned Nanoda retry for worker-stack overflow; no proof/axiom changes."""
from __future__ import annotations
import argparse
import hashlib
import json
import resource
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    args = parser.parse_args()
    export = args.export.resolve(strict=True)
    prefix = (ROOT / '.local/lean-4.35.0-linux').resolve(strict=True)
    binary = prefix / 'bin/nanoda_bin'
    sandbox = shutil.which('bwrap')
    if not sandbox:
        raise RuntimeError('bwrap is required; no unsandboxed fallback')
    config = ROOT / 'tmp/verification/nanoda-serial' / (export.parent.name + '.json')
    config.parent.mkdir(parents=True,exist_ok=True)
    config.write_text(json.dumps({'use_stdin':False,'export_file_path':str(export),
        'permitted_axioms':['propext','Quot.sound','Classical.choice'],
        'unpermitted_axiom_hard_error':False,'num_threads':1,
        'nat_extension':True,'string_extension':True,'print_success_message':True,'print_axioms':False})+'\n')
    argv = [sandbox,'--ro-bind','/','/','--tmpfs','/home','--tmpfs','/root',
        '--tmpfs','/run/user','--tmpfs','/tmp','--dir','/tmp/home',
        '--dev','/dev','--proc','/proc','--clearenv','--tmpfs','/run','--tmpfs','/var']
    for path in [config,export,binary,prefix]:
        argv += ['--ro-bind',str(path),str(path)]
    argv += ['--setenv','LEAN_ABORT_ON_PANIC','1','--setenv','HOME','/tmp/home',
        '--unshare-all','--die-with-parent','--new-session','--chdir','/tmp','--',str(binary),str(config)]
    soft,hard = resource.getrlimit(resource.RLIMIT_STACK)
    stack = 256 * 1024 * 1024
    if hard != resource.RLIM_INFINITY and hard < stack:
        raise RuntimeError('Process hard stack limit does not permit 256 MiB')
    resource.setrlimit(resource.RLIMIT_STACK,(stack,hard))
    print(json.dumps({'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
        'export_sha256':hashlib.sha256(export.read_bytes()).hexdigest(),
        'config':json.loads(config.read_text()),'stack_bytes':stack,'command':argv}),flush=True)
    return subprocess.run(argv,check=False).returncode

if __name__ == '__main__':
    raise SystemExit(main())
