#!/usr/bin/env python3
"""Generate explicit experiment filters for review/copying; never changes a device."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STRATEGIES = ('no-tweak', 'existing', 'service-only', 'system-only', 'minimal')


def parse_filter(text):
    # Baseline filters use only string arrays and a single Filter dictionary.
    return {'Filter': {key: re.findall(r'"([^"]+)"', value)
                       for key, value in re.findall(r'(Bundles|Executables)\s*=\s*\((.*?)\)', text, re.S)}}


def prepare(strategy, output, client_bundle=None, client_process=None):
    if bool(client_bundle) != bool(client_process): raise ValueError('Specify both client bundle and executable process name')
    if client_bundle and (strategy != 'minimal' or not re.fullmatch(r'[A-Za-z0-9.-]+', client_bundle) or
                          not client_process or len(client_process.encode()) > 128 or re.search(r'[/\\*?\[\]]', client_process)):
        raise ValueError('Only minimal strategy accepts one exact opt-in client; no wildcard or path')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    disabled = {'Filter': {'Executables': ['AirPodsCompat-Disabled-Experiment']}}
    main = parse_filter((ROOT / 'tweak/AirPodsCompat.plist').read_text())
    resource = parse_filter((ROOT / 'tweak/AirPodsCompatResources.plist').read_text())
    controls = parse_filter((ROOT / 'tweak/AirPodsCompatControls.plist').read_text())
    if strategy == 'no-tweak': main = resource = controls = disabled
    elif strategy == 'service-only':
        main = {'Filter': {'Executables': ['bluetoothd', 'bluetoothuserd', 'bluetoothaudiod', 'uarpd']}}
        resource = disabled
        controls = disabled
    elif strategy == 'system-only':
        resource = parse_filter((ROOT / 'packaging/resource-filters/system-only.plist').read_text())
    elif strategy == 'existing':
        for name in ['AirPodsCompat', 'AirPodsCompatResources']:
            text = subprocess.check_output(['git', 'show', f'a30615d:tweak/{name}.plist'], cwd=ROOT).decode()
            (output / f'{name}.plist').write_text(text, encoding='utf-8')
        (output / 'AirPodsCompatControls.plist').write_bytes(plistlib.dumps(disabled))
        return
    if client_bundle:
        resource['Filter'].setdefault('Bundles', []).append(client_bundle)
        (output / 'ExtraResourceClients.plist').write_bytes(plistlib.dumps({'ExtraResourceClientProcesses': [client_process]}))
    for name, value in [('AirPodsCompat', main), ('AirPodsCompatResources', resource), ('AirPodsCompatControls', controls)]:
        (output / f'{name}.plist').write_bytes(plistlib.dumps(value))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--strategy', choices=STRATEGIES, required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--client-bundle')
    parser.add_argument('--client-process')
    args = parser.parse_args()
    prepare(args.strategy, args.out, args.client_bundle, args.client_process)
    print(f'Prepared {args.strategy} filters in {args.out}; restart affected processes only after installing the reviewed filters.')
