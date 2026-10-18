#!/usr/bin/env python3
"""Opt-in physical iPhone verification using a Release ROUTING_BENCHMARK build.
Inputs are copied to the app container's tmp, leaving the installed timetable and transfer walks intact.

Default: depart, arrive and recorded-live on --database and --fixture, anchored on 2026-10-08.
With --capture-directory: replays a live capture (live-now by default) at --epoch, priming and warm
samples in one launch and every cold sample in a fresh launch. A replay never contacts ATP: the
request budget is 0, a launch without capture bodies fails before its first search, and a board
query missing from the capture fails the run.

Every sample records ProcessInfo.thermalState; samples taken in the serious or critical state are
dropped into dropped.json.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--device', required=True)
parser.add_argument('--app', type=Path, help='Release ROUTING_BENCHMARK build; required unless --no-install')
parser.add_argument('--no-install', action='store_true', help='Keep the installed build')
parser.add_argument('--database', required=True, type=Path)
parser.add_argument('--fixture', type=Path, help='Recorded board for the default scenarios')
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--transfer-walks', choices=['on', 'off'], default='on',
    help='on builds the stored transfer walk table in its own launch before the measured scenarios')
parser.add_argument('--samples', type=int, default=4, help='Default scenarios: measured samples after priming')
parser.add_argument('--capture-directory', type=Path, help='Replay this capture (metadata and body files)')
parser.add_argument('--bike-fixture', type=Path, help='Replay: recorded bike availability snapshot')
parser.add_argument('--epoch', type=float, help='Replay: Unix planning timestamp of the captured sample')
parser.add_argument('--replay-latency', action='store_true',
    help='Replay: answer each board after its recorded server wait and transfer')
parser.add_argument('--scenario', default='live-now', help='Replay scenario')
parser.add_argument('--warm', type=int, default=1, help='Replay: warm samples after one priming operation')
parser.add_argument('--cold', type=int, default=1, help='Replay: fresh-process samples')
parser.add_argument('--full-evidence', action='store_true', help='Export complete plans, as the simulator replays do')
args = parser.parse_args()
replay = args.capture_directory is not None
if not args.no_install and args.app is None:
    parser.error('--app is required unless --no-install')
if replay:
    if args.bike_fixture is None or args.epoch is None:
        parser.error('--capture-directory requires --bike-fixture and --epoch')
    bodies = list(args.capture_directory.glob('*.body.json'))
    if not bodies or len(list(args.capture_directory.glob('*.json'))) != 2 * len(bodies):
        parser.error('--capture-directory must hold metadata and body files in pairs')
    if args.warm < 0 or args.cold < 0 or args.warm + args.cold + 1 > 5:
        parser.error('Each case permits at most five operations, including one priming operation')
else:
    if args.fixture is None:
        parser.error('--fixture is required without --capture-directory')
    if args.samples < 0 or args.samples + 1 > 5:
        parser.error('Each case permits at most five operations, including one priming operation')
args.output.mkdir(parents=True, exist_ok=True)
bundle = 'dev.pedrocordeiro.Verkeier'
domain = ['--device', args.device, '--domain-type', 'appDataContainer', '--domain-identifier', bundle]
if not args.no_install:
    subprocess.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device, str(args.app)], check=True)
subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'details', '--device', args.device,
    '--json-output', str(args.output / 'device.json')], check=True, stdout=subprocess.DEVNULL)


def copy_to(source, name):
    # Never pass --remove-existing-content: it empties the parent tmp directory, not just the destination.
    subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'to', *domain,
        '--source', str(source), '--destination', 'tmp/' + name], check=True, stdout=subprocess.DEVNULL)


def copy_from(name, destination):
    subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'from', *domain,
        '--source', 'tmp/' + name, '--destination', str(destination)], check=True, stdout=subprocess.DEVNULL)


# Replays keep the feed's file name, so the timetable identity matches the simulator's installed copy.
database = args.database.name if replay else 'benchmark-feed.sqlite'
copy_to(args.database, database)
if replay:
    # Named after its contents, so files of another capture copied earlier cannot join the replay.
    listing = sorted(f'{file.name}:{file.stat().st_size}' for file in args.capture_directory.iterdir())
    capture = 'benchmark-capture-' + hashlib.sha256('\n'.join(listing).encode()).hexdigest()[:12]
    copy_to(args.capture_directory, capture)
    copy_to(args.bike_fixture, 'benchmark-bikes.json')
else:
    copy_to(args.fixture, 'benchmark-board.json')


def launch(scenario, settings, label):
    """One app process; returns its console text once it reports completion."""
    log = args.output / f'{scenario}-{label}.log'
    settings = settings | {'ROUTING_BENCHMARK_SCENARIO': scenario}
    env = os.environ | {'DEVICECTL_CHILD_' + key: value for key, value in settings.items()}
    with log.open('w') as stream:
        process = subprocess.Popen(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
            '--console', '--terminate-existing', bundle, '--routing-benchmark'], env=env,
            stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 600
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
            if 'ROUTING_BENCHMARK_ABORT' in text or 'ROUTING_BENCHMARK_FAILED' in text:
                raise RuntimeError(f'Benchmark failed; see {log}')
            if 'ROUTING_BENCHMARK_DONE' not in text:
                raise RuntimeError(f'Application exited before completion; see {log}')
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
    if any(line.startswith('ROUTING_NETWORK_REQUEST ') for line in text.splitlines()):
        raise RuntimeError(f'A launch sent an ATP request; see {log}')
    return text


common = {'ROUTING_BENCHMARK_DATABASE': database}
if args.transfer_walks == 'off':
    common['ROUTING_TRANSFER_WALKS'] = '0'
else:
    # The store directory is read at launch and must be absolute, so ask the container for its path.
    home = next(line.split(' ', 1)[1].strip() for line in launch('probe-container', {}, 'probe').splitlines()
        if line.startswith('ROUTING_BENCHMARK_HOME '))
    common['ROUTING_TRANSFER_WALKS_DIRECTORY'] = home + '/tmp/benchmark-transfer-walks'
    text = launch('optimise-transfer-walks', common | {'ROUTING_BENCHMARK_REBUILD': '1'}, 'optimise')
    for line in text.splitlines():
        if line.startswith('ROUTING_BENCHMARK_OPTIMISATION '):
            (args.output / 'optimisation.json').write_text(line.split(' ', 1)[1])
            print('transfer walks:', line.split(' ', 1)[1], flush=True)

records = []
dropped = []


def collect(text, scenario, process, expected):
    files = [line for line in text.splitlines() if line.startswith('ROUTING_BENCHMARK_FILE ')]
    if len(files) != expected:
        raise RuntimeError(f'Expected {expected} samples from {scenario} {process}, received {len(files)}')
    for line in text.splitlines():
        if line.startswith('ROUTING_BENCHMARK_FILE '):
            name = Path(line.split(' ', 1)[1].strip()).name
            destination = args.output / name
            copy_from(name, destination)
            value = json.loads(destination.read_text())
            destination.unlink()
            value['process'] = process if process == 'cold' else ('priming' if value['sample'] == 0 else 'warm')
            states = {value.get('thermalStateAtStart'), value.get('thermalStateAtEnd')}
            (dropped if states & {'serious', 'critical'} else records).append(value)
        if line.startswith('ROUTING_BIKE_FILE '):
            copy_from(Path(line.split(' ', 1)[1].strip()).name, args.output / 'bike-snapshot.json')
    (args.output / 'samples.json').write_text(json.dumps(records, indent=2))
    (args.output / 'dropped.json').write_text(json.dumps(dropped, indent=2))


if replay:
    settings = common | {'ROUTING_BENCHMARK_CAPTURE_DIRECTORY': capture,
        'ROUTING_BENCHMARK_BIKE_FIXTURE': 'benchmark-bikes.json',
        'ROUTING_BENCHMARK_EPOCH': repr(args.epoch),
        'ROUTING_BENCHMARK_REPLAY_ONLY': '1',
        'ROUTING_BENCHMARK_REQUEST_BUDGET': '0',
        'ROUTING_BENCHMARK_COMPOSITION': 'production',
        'ROUTING_BENCHMARK_FULL_MAP': '0',
        'ROUTING_BENCHMARK_FULL_EVIDENCE': '1' if args.full_evidence else '0',
        'ROUTING_BENCHMARK_AVOID_TIGHT_TRANSFERS': '0'}
    if args.replay_latency:
        settings['ROUTING_BENCHMARK_REPLAY_LATENCY'] = '1'
    runs = [(args.warm + 1, 'warm', 'warm')] + [(1, f'cold-{n + 1}', 'cold') for n in range(args.cold)]
    for samples, label, process in runs:
        text = launch(args.scenario, settings | {'ROUTING_BENCHMARK_SAMPLES': str(samples)}, label)
        queries = [line.split(' ', 1)[1].strip() for line in text.splitlines()
            if line.startswith('ROUTING_BENCHMARK_REPLAY_QUERIES ')]
        if not queries:
            raise RuntimeError(f'Launch {label} did not confirm its replay capture')
        collect(text, args.scenario, process, samples)
        print(f'{args.scenario} {label} complete', flush=True)
    scenarios = [args.scenario]
else:
    scenarios = ['depart', 'arrive', 'recorded-live']
    anchors = {'depart': '2026-10-08T08:00:00+02:00', 'arrive': '2026-10-08T09:00:00+02:00',
        'recorded-live': '2026-10-08T18:28:00+02:00'}
    for scenario in scenarios:
        text = launch(scenario, common | {'ROUTING_BENCHMARK_SAMPLES': str(args.samples + 1),
            'ROUTING_BENCHMARK_TIME': anchors[scenario],
            'ROUTING_BENCHMARK_FIXTURE': 'benchmark-board.json',
            'ROUTING_BENCHMARK_COMPOSITION': 'transit',
            'ROUTING_BENCHMARK_FULL_MAP': '1'}, 'warm')
        collect(text, scenario, 'warm', args.samples + 1)
        print(scenario, 'complete', flush=True)

if len({v['requestID'] for v in records + dropped}) != len(records + dropped):
    raise RuntimeError('A sample reused stale diagnostics instead of calculating a fresh result')
(args.output / 'metadata.json').write_text(json.dumps({'app': str(args.app) if args.app else None,
    'database': str(args.database), 'capture': str(args.capture_directory) if replay else None,
    'epoch': args.epoch, 'replayLatency': args.replay_latency,
    'replayQueries': int(queries[0]) if replay else None,
    'transferWalksDirectory': common.get('ROUTING_TRANSFER_WALKS_DIRECTORY')}, indent=2))
summary = []
for scenario in scenarios:
    for kind in ['priming', 'warm', 'cold']:
        values = [v for v in records if v['scenario'] == scenario and v['process'] == kind]
        if not values:
            continue
        times = sorted(v['total_ms'] for v in values)
        summary.append({'scenario': scenario, 'process': kind, 'samples': len(times),
            'median_ms': statistics.median(times), 'p95_ms': times[math.ceil(len(times) * .95) - 1],
            'maximum_ms': max(times), 'peak_memory_bytes': max(v['peak_memory_bytes'] for v in values),
            'thermal_states': sorted({v.get('thermalStateAtStart', '') for v in values}
                | {v.get('thermalStateAtEnd', '') for v in values}),
            'median_stages_ms': {stage: statistics.median(v['stages_ms'].get(stage, 0) for v in values)
                for stage in sorted(set().union(*(v['stages_ms'] for v in values)))},
            'median_counters': {counter: statistics.median(v['counters'].get(counter, 0) for v in values)
                for counter in sorted(set().union(*(v['counters'] for v in values)))}})
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2))
for row in summary:
    print(f'{row["scenario"]} {row["process"]}: {row["samples"]} samples, median {row["median_ms"]:.0f} ms, '
          f'maximum {row["maximum_ms"]:.0f} ms, thermal {",".join(row["thermal_states"])}', flush=True)
if dropped:
    print(f'{len(dropped)} samples dropped for the serious or critical thermal state; see dropped.json', flush=True)
