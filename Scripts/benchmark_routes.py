#!/usr/bin/env python3
"""Run the opt-in production route-sheet benchmark without a debugger.
Build Release with ENABLE_CODE_COVERAGE=NO first; install GTFS/Valhalla in the app.
"""
import argparse
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', help='Simulator UDID; defaults to the available iPhone 17')
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--scenarios', nargs='+', default=['depart', 'reverse', 'coordinates', 'arrive', 'exact', 'rural', 'paging', 'refresh', 'recorded-live', 'deadline-arrive', 'cached'])
parser.add_argument('--warm', type=int, default=20)
parser.add_argument('--cold', type=int, default=10)
parser.add_argument('--p95-limit-ms', type=float, default=5000, help='Gate threshold; use 0 for a separate Debug audit')
args = parser.parse_args()
if args.device is None:
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
    matches = [d for devices in inventory['devices'].values() for d in devices if d.get('isAvailable') and d['name'] == 'iPhone 17']
    if not matches:
        parser.error('No available iPhone 17 simulator; specify --device')
    device = next((d for d in matches if d['state'] == 'Booted'), matches[0])
    args.device = device['udid']
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', args.device], check=True)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', args.device, '-b'], check=True)
args.output.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parent.parent
fixture = repo / 'VerkéierTests/Fixtures/esch-delayed-passlist.json'
subprocess.run(['xcrun', 'simctl', 'install', args.device, str(args.app)], check=True)
records = []
cached_records = []

def run(scenario, samples, label):
    log = args.output / f'{scenario}-{label}.log'
    env = os.environ | {'SIMCTL_CHILD_ROUTING_BENCHMARK_SCENARIO': scenario,
        'SIMCTL_CHILD_ROUTING_BENCHMARK_SAMPLES': str(samples),
        'SIMCTL_CHILD_ROUTING_BENCHMARK_FIXTURE': str(fixture)}
    with log.open('w') as stream:
        process = subprocess.Popen(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
            args.device, 'dev.pedrocordeiro.Verkeier', '--routing-benchmark'], env=env, stdout=stream, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + max(180, samples * 130)
        try:
            while process.poll() is None:
                text = log.read_text(errors='replace')
                if 'ROUTING_BENCHMARK_FAILED' in text:
                    raise RuntimeError(f'Benchmark failed; see {log}')
                if 'ROUTING_BENCHMARK_DONE' in text:
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'Benchmark timeout; see {log}')
                time.sleep(.2)
            text = log.read_text(errors='replace')
            if 'ROUTING_BENCHMARK_DONE' not in text:
                raise RuntimeError(f'App exited before rendering results; see {log}')
        finally:
            subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'dev.pedrocordeiro.Verkeier'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            process.wait(timeout=10)
    values = [json.loads(line.split('ROUTING_BENCHMARK ', 1)[1]) for line in text.splitlines() if line.startswith('ROUTING_BENCHMARK {')]
    for line in text.splitlines():
        if line.startswith('ROUTING_BENCHMARK_FILE '):
            path = Path(line.split(' ', 1)[1])
            values.append(json.loads(path.read_text()))
            path.unlink()
    for line in text.splitlines():
        if line.startswith('ROUTING_CACHED_COMPARISON_FILE '):
            path = Path(line.split(' ', 1)[1])
            cached_records.append(json.loads(path.read_text()) | {'scenario': scenario})
            path.unlink()
    if cached_records:
        (args.output / 'cached-comparisons.json').write_text(json.dumps(cached_records, indent=2))
    if len(values) != samples:
        raise RuntimeError(f'Expected {samples} rendered samples, received {len(values)}')
    if len({v['requestID'] for v in values}) != samples:
        raise RuntimeError('A sample reused stale diagnostics instead of calculating a fresh result')
    for value in values:
        if scenario == 'cached' and value['counters'].get('networkRequests', 0) != 0:
            raise RuntimeError('Fully cached search issued a board request')
        # The first calculation in a warm series is a priming operation.
        value['process'] = 'cold' if label.startswith('cold') else ('priming' if value['sample'] == 0 else 'warm')
        records.append(value)
    (args.output / 'samples.json').write_text(json.dumps(records, indent=2))
    print(f'{scenario} {label}: {len(values)} completed; maximum {max(v["total_ms"] for v in values):.0f} ms', flush=True)

for scenario in args.scenarios:
    run(scenario, args.warm + 1, 'warm')
    for sample in range(args.cold):
        run(scenario, 1, f'cold-{sample + 1}')

summary = []
for scenario in args.scenarios:
    for kind in ['warm', 'cold']:
        values = [v for v in records if v['scenario'] == scenario and v['process'] == kind]
        times = sorted(v['total_ms'] for v in values)
        if not times:
            continue
        summary.append({'scenario': scenario, 'process': kind, 'samples': len(times),
            'median_ms': statistics.median(times), 'p95_ms': times[math.ceil(len(times) * .95) - 1],
            'maximum_ms': max(times), 'peak_memory_bytes': max(v['peak_memory_bytes'] for v in values),
            'median_observed_departure_coverage': statistics.median(
                sum(leg['departureSource'] == 'observed' for leg in v.get('displayedLegs', [])) / max(1, len(v.get('displayedLegs', []))) for v in values),
            'median_stages_ms': {stage: statistics.median(v['stages_ms'].get(stage, 0) for v in values)
                for stage in sorted(set().union(*(v['stages_ms'] for v in values)))},
            'median_counters': {counter: statistics.median(v['counters'].get(counter, 0) for v in values)
                for counter in sorted(set().union(*(v['counters'] for v in values)))}})
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
failures = [row for row in summary if args.p95_limit_ms > 0 and row['p95_ms'] > args.p95_limit_ms]
if failures:
    raise RuntimeError('Rendered p95 exceeded the gate: ' + ', '.join(
        f'{row["scenario"]} {row["process"]} {row["p95_ms"]:.0f} ms' for row in failures))
