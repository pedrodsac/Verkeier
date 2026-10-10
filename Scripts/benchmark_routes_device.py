#!/usr/bin/env python3
"""Opt-in physical iPhone verification using a Release ROUTING_BENCHMARK build.
The feed and recorded boards are copied to temporary files, leaving installed data intact.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--database', required=True, type=Path)
parser.add_argument('--fixture', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--samples', type=int, default=5)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
bundle = 'dev.pedrocordeiro.Verkeier'
domain = ['--device', args.device, '--domain-type', 'appDataContainer', '--domain-identifier', bundle]
subprocess.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device, str(args.app)], check=True)
for source, name in [(args.database, 'benchmark-feed.sqlite'), (args.fixture, 'benchmark-board.json')]:
    subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'to', *domain,
        '--source', str(source), '--destination', 'tmp/' + name], check=True)
records = []
for scenario, anchor in [('depart', '2026-10-08T08:00:00+02:00'),
                         ('arrive', '2026-10-08T09:00:00+02:00'),
                         ('recorded-live', '2026-10-08T18:28:00+02:00')]:
    log = args.output / (scenario + '.log')
    env = os.environ | {'DEVICECTL_CHILD_ROUTING_BENCHMARK_SCENARIO': scenario,
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_SAMPLES': str(args.samples + 1),
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_TIME': anchor,
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_DATABASE': 'benchmark-feed.sqlite',
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_FIXTURE': 'benchmark-board.json',
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_COMPOSITION': 'transit',
        'DEVICECTL_CHILD_ROUTING_BENCHMARK_FULL_MAP': '1'}
    with log.open('w') as stream:
        process = subprocess.Popen(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
            '--console', '--terminate-existing', bundle, '--routing-benchmark'], env=env,
            stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + max(180, args.samples * 130)
            while process.poll() is None:
                text = log.read_text(errors='replace')
                if 'ROUTING_BENCHMARK_FAILED' in text or 'ROUTING_BENCHMARK_ABORT' in text:
                    raise RuntimeError(f'Benchmark failed; see {log}')
                if 'ROUTING_BENCHMARK_DONE' in text:
                    break
                if time.monotonic() > deadline:
                    raise TimeoutError(f'Benchmark timeout; see {log}')
                time.sleep(.2)
            text = log.read_text(errors='replace')
            if 'ROUTING_BENCHMARK_DONE' not in text:
                raise RuntimeError(f'Application exited before completion; see {log}')
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
    for line in text.splitlines():
        if line.startswith('ROUTING_BENCHMARK_FILE '):
            name = Path(line.split(' ', 1)[1]).name
            destination = args.output / name
            subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'from', *domain,
                '--source', 'tmp/' + name, '--destination', str(destination)], check=True, stdout=subprocess.DEVNULL)
            value = json.loads(destination.read_text())
            value['process'] = 'priming' if value['sample'] == 0 else 'warm'
            records.append(value)
    (args.output / 'samples.json').write_text(json.dumps(records, indent=2))
    print(scenario, 'complete', flush=True)
