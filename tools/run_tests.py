#!/usr/bin/env python3
"""Host policy and repository integration checks. No physical-device assertions."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default=os.environ.get('CC', 'clang'))
    parser.add_argument('--zig', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='airpodscompat-tests-') as output:
        for source in sorted((ROOT / 'tests').glob('*.c')):
            binary = Path(output) / (source.stem + ('.exe' if os.name == 'nt' else ''))
            command = [args.compiler] + (['cc'] if args.zig else [])
            subprocess.run(command + ['-std=c11', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
            print(f'PASS {source.name}', flush=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_registry.py')], check=True)
    subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
