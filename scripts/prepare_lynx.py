"""Apply the maintained module-runner extension to the pinned local Lynx checkout."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def prepare() -> None:
    dependency = ROOT / 'deps/lynx'
    patch = ROOT / 'verification/patches/lynx-parallel-runner.patch'
    if not dependency.is_dir():
        return
    if subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=dependency,
                      capture_output=True).returncode == 0:
        return
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=dependency, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=dependency, check=True)


if __name__ == '__main__':
    prepare()
