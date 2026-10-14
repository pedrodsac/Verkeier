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
parser.add_argument('--fixture', type=Path, help='Recorded ATP board, with dates matching --time')
parser.add_argument('--capture-directory', type=Path, help='Replay successful transport capture for identical board queries')
parser.add_argument('--bike-fixture', type=Path, help='Recorded bike availability snapshot')
parser.add_argument('--composition', choices=['transit', 'production'], default='production')
parser.add_argument('--full-map', action='store_true')
parser.add_argument('--full-evidence', action='store_true', help='Export complete plans; use separately from memory measurements')
parser.add_argument('--request-budget', type=int, default=200, help='Maximum ATP requests across this invocation')
parser.add_argument('--live-concurrency', type=int, help='Explicit benchmark override; production remains at its default')
parser.add_argument('--compare-boards', action='store_true', help='Extra opt-in board equivalence requests')
parser.add_argument('--warm', type=int, default=2, help='Warm samples after one priming operation')
parser.add_argument('--cold', type=int, default=2, help='Fresh-process samples; at most five operations total per case')
parser.add_argument('--epoch', type=float, help='Exact Unix planning timestamp from a captured sample')
parser.add_argument('--verify-kernel', action='store_true', help='Quality verification only; changes CPU timings')
parser.add_argument('--time', help='Fixed ISO 8601 planning time for comparison with another journey planner')
parser.add_argument('--destination-name', help='Destination label for a custom comparison')
parser.add_argument('--destination-coordinate', nargs=2, type=float, metavar=('LATITUDE', 'LONGITUDE'))
parser.add_argument('--destination-stop', help='GTFS stop ID at the custom destination')
parser.add_argument('--origin-name', help='Origin label for a custom comparison')
parser.add_argument('--origin-coordinate', nargs=2, type=float, metavar=('LATITUDE', 'LONGITUDE'))
parser.add_argument('--origin-stop', help='GTFS stop ID at the custom origin')
parser.add_argument('--avoid-tight-transfers', action='store_true', help='Avoid transfers with less than three minutes available')
parser.add_argument('--transfer-walks', choices=['on', 'off', 'verify'], default='on',
    help='Stored transfer walks: on builds a table in a separate process first, off ignores the table, '
         'verify also recomputes every stored walk live and fails on any difference')
parser.add_argument('--rebuild-transfer-walks', action='store_true', help='Ignore an existing table when building it')
parser.add_argument('--maximum-limit-ms', '--p95-limit-ms', dest='maximum_limit_ms', type=float,
    default=5000, help='Every operation must be below this threshold, including priming; use 0 for a separate Debug audit')
args = parser.parse_args()
if (args.destination_name or args.destination_stop) and not args.destination_coordinate:
    parser.error('Custom destination requires --destination-coordinate LATITUDE LONGITUDE')
if (args.origin_name or args.origin_stop) and not args.origin_coordinate:
    parser.error('Custom origin requires --origin-coordinate LATITUDE LONGITUDE')
if args.warm < 0 or args.cold < 0 or args.warm + args.cold + 1 > 5:
    parser.error('Each case permits at most five operations, including one priming operation')
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
fixture = args.fixture or repo / 'VerkéierTests/Fixtures/esch-delayed-passlist.json'
network_requests = 0
network_records = []
subprocess.run(['xcrun', 'simctl', 'install', args.device, str(args.app)], check=True)
records = []
cached_records = []

def run(scenario, samples, label):
    global network_requests
    log = args.output / f'{scenario}-{label}.log'
    env = os.environ | {'SIMCTL_CHILD_ROUTING_BENCHMARK_SCENARIO': scenario,
        'SIMCTL_CHILD_ROUTING_BENCHMARK_SAMPLES': str(samples),
        'SIMCTL_CHILD_ROUTING_BENCHMARK_FIXTURE': str(fixture.resolve()),
        'SIMCTL_CHILD_ROUTING_BENCHMARK_COMPOSITION': args.composition,
        'SIMCTL_CHILD_ROUTING_BENCHMARK_FULL_MAP': '1' if args.full_map else '0',
        'SIMCTL_CHILD_ROUTING_BENCHMARK_FULL_EVIDENCE': '1' if args.full_evidence else '0',
        'SIMCTL_CHILD_ROUTING_BENCHMARK_COMPARE_BOARDS': '1' if args.compare_boards else '0',
        'SIMCTL_CHILD_ROUTING_BENCHMARK_REQUEST_BUDGET': str(max(0, args.request_budget - network_requests))}
    if args.live_concurrency is not None:
        env["SIMCTL_CHILD_ROUTING_BENCHMARK_LIVE_CONCURRENCY"] = str(args.live_concurrency)
    if args.transfer_walks == 'off':
        env['SIMCTL_CHILD_ROUTING_TRANSFER_WALKS'] = '0'
    else:
        # A separate directory keeps benchmark tables out of the app's own container data.
        env['SIMCTL_CHILD_ROUTING_TRANSFER_WALKS_DIRECTORY'] = str((args.output / 'transfer-walks').resolve())
        if args.transfer_walks == 'verify':
            env['SIMCTL_CHILD_ROUTING_TRANSFER_WALKS'] = 'verify'
    if args.rebuild_transfer_walks:
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_REBUILD'] = '1'
    if args.capture_directory:
        env["SIMCTL_CHILD_ROUTING_BENCHMARK_CAPTURE_DIRECTORY"] = str(args.capture_directory.resolve())
    if args.bike_fixture:
        env["SIMCTL_CHILD_ROUTING_BENCHMARK_BIKE_FIXTURE"] = str(args.bike_fixture.resolve())
    if args.epoch is not None:
        env["SIMCTL_CHILD_ROUTING_BENCHMARK_EPOCH"] = repr(args.epoch)
    if args.verify_kernel:
        env["SIMCTL_CHILD_ROUTING_VERIFY_KERNEL"] = "1"
    if args.time:
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_TIME'] = args.time
    if args.destination_coordinate:
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_DESTINATION_LATITUDE'] = str(args.destination_coordinate[0])
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_DESTINATION_LONGITUDE'] = str(args.destination_coordinate[1])
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_DESTINATION_NAME'] = args.destination_name or 'Destination'
        if args.destination_stop:
            env['SIMCTL_CHILD_ROUTING_BENCHMARK_DESTINATION_STOP'] = args.destination_stop
    if args.origin_coordinate:
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_ORIGIN_LATITUDE'] = str(args.origin_coordinate[0])
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_ORIGIN_LONGITUDE'] = str(args.origin_coordinate[1])
        env['SIMCTL_CHILD_ROUTING_BENCHMARK_ORIGIN_NAME'] = args.origin_name or 'Origin'
        if args.origin_stop:
            env['SIMCTL_CHILD_ROUTING_BENCHMARK_ORIGIN_STOP'] = args.origin_stop
    env['SIMCTL_CHILD_ROUTING_BENCHMARK_AVOID_TIGHT_TRANSFERS'] = '1' if args.avoid_tight_transfers else '0'
    with log.open('w') as stream:
        process = subprocess.Popen(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
            args.device, 'dev.pedrocordeiro.Verkeier', '--routing-benchmark'], env=env, stdout=stream, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + max(180, samples * 130)
        failure = None
        try:
            while process.poll() is None:
                text = log.read_text(errors='replace')
                if 'ROUTING_BENCHMARK_ABORT' in text:
                    raise RuntimeError(f'Live benchmark stopped (quota, budget or capture failure); see {log}')
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
        except Exception as error:
            failure = error
        finally:
            subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'dev.pedrocordeiro.Verkeier'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            process.wait(timeout=10)
    if scenario == 'optimise-transfer-walks':
        if failure is not None:
            raise failure
        for line in text.splitlines():
            if line.startswith('ROUTING_BENCHMARK_OPTIMISATION '):
                (args.output / 'optimisation.json').write_text(line.split(' ', 1)[1])
                print('transfer walks:', line.split(' ', 1)[1], flush=True)
        return
    network_requests += sum(line.startswith("ROUTING_NETWORK_REQUEST ") for line in text.splitlines())
    for line in text.splitlines():
        if line.startswith("ROUTING_BIKE_FILE "):
            source = Path(line.split(" ", 1)[1])
            (args.output / "bike-snapshot.json").write_bytes(source.read_bytes())
    capture = args.output / "network"
    for line in text.splitlines():
        if line.startswith("ROUTING_NETWORK_FILE "):
            source = Path(line.split(" ", 1)[1])
            metadata = json.loads(source.read_text())
            capture.mkdir(exist_ok=True)
            if body := metadata.get("body"):
                source_body = Path(body)
                target_body = capture / source_body.name
                target_body.write_bytes(source_body.read_bytes())
                metadata["body"] = target_body.name
            (capture / source.name).write_text(json.dumps(metadata, indent=2))
            network_records.append(metadata)
    (args.output / "transport.json").write_text(json.dumps(network_records, indent=2))
    if failure is not None:
        (args.output / "aborted.json").write_text(json.dumps({"scenario": scenario, "reason": str(failure), "requests": network_requests}, indent=2))
        raise failure
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

if args.transfer_walks != 'off':
    # Built once in its own process, so measured fresh-process samples start from the stored table.
    run('optimise-transfer-walks', 1, 'optimise')
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
failures = [row for row in records if args.maximum_limit_ms > 0 and row['total_ms'] >= args.maximum_limit_ms]
if failures:
    raise RuntimeError('Rendered operation reached or exceeded the gate: ' + ', '.join(
        f'{row["scenario"]} {row["process"]} sample {row["sample"]}: {row["total_ms"]:.0f} ms' for row in failures))
