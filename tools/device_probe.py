#!/usr/bin/env python3
"""Capture read-only, process-specific Frida observations over an existing tunnel.

Requires frida-tools (with its ObjC bridge). Does not install or launch a server.
Use a loopback SSH tunnel, not an unauthenticated LAN listener.
"""
import argparse
import datetime
import json
from pathlib import Path
import threading


def main():
    import frida
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='127.0.0.1:27042')
    parser.add_argument('--process', default='SpringBoard')
    parser.add_argument('--strategy', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--bridge', help='Optional compiled ObjC bridge JS prefix for Frida 17+')
    parser.add_argument('--script', help='Use another explicitly selected probe JS file')
    parser.add_argument('--mode-command', action='store_true', help='Label an explicitly authorized native listening-mode write/readback experiment')
    args = parser.parse_args()
    device = frida.get_device_manager().add_remote_device(args.device)
    process = next(p for p in device.enumerate_processes() if p.name == args.process)
    script_path = Path(args.script) if args.script else Path(__file__).resolve().parents[1] / 'analysis/runtime_probe.js'
    source = script_path.read_text(encoding='utf-8')
    if args.bridge:
        source = Path(args.bridge).read_text(encoding='utf-8') + '\nglobalThis.ObjC = bridge;\n' + source
    completed = threading.Event()
    result = {}

    def receive(message, _data):
        result.update(message=message, strategy=args.strategy,
                      timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      instrumentation=('temporary native listening-mode command/readback; original mode restored by script'
                                       if args.mode_command else 'read-only Frida attachment; no compatibility hook installed by probe'))
        completed.set()

    session = device.attach(process.pid)
    try:
        script = session.create_script(source)
        script.on('message', receive)
        script.load()
        if not completed.wait(25): raise TimeoutError('No probe result; verify bridge and main-queue availability')
        if result['message']['type'] != 'send': raise RuntimeError(result['message'])
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
        print(f'Captured {args.process} / {args.strategy} -> {args.out}')
    finally:
        session.detach()


if __name__ == '__main__':
    main()
