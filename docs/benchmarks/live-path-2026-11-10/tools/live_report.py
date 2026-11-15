#!/usr/bin/env python3
"""Summarises a live A/B/C round: per-sample timings, the first burst, the later boards, and the
ATP wait of boards that every arm asked.  usage: live_report.py <round dir>"""
import json, re, statistics, sys
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlparse, parse_qs

root = Path(sys.argv[1])
samples = []
for run in sorted(root.iterdir(), key=lambda p: int(p.name.split('-')[0]) if p.is_dir() else 0):
    if not run.is_dir() or not (run / 'samples.json').exists():
        continue
    number, arm, scenario = run.name.split('-', 2)
    for sample in json.loads((run / 'samples.json').read_text()):
        requests = []
        first = min(t['metrics']['taskStart'] for t in sample['transport'])
        for t in sample['transport']:
            metrics = t['metrics']
            query = parse_qs(urlparse(t['request']).query)
            upstream = re.search(r'upstream;dur=([\d.]+)', metrics.get('serverTiming') or '')
            requests.append({'key': (query['id'][0], query.get('lines', [''])[0]),
                             'start': (metrics['taskStart'] - first) * 1000,
                             'end': (metrics['taskEnd'] - first) * 1000,
                             'upstream': float(upstream[1]) if upstream else None,
                             'wait': sum(x.get('responseWaitMilliseconds', 0) for x in metrics['transactions']),
                             'bytes': sum(x.get('encodedResponseBytes', 0) for x in metrics['transactions'])})
        burst = [r for r in requests if r['start'] < 50]
        later = [r for r in requests if r['start'] >= 50]
        span = lambda stage: [(p['start_ms'], p['start_ms'] + p['duration_ms']) for p in sample['spans'] if p['stage'] == stage]
        realtime = span('realtime')
        samples.append({'run': run.name, 'arm': arm, 'scenario': scenario, 'process': sample.get('process', sample['sample']),
                        'total': sample['total_ms'], 'realtime': realtime[0][1] - realtime[0][0],
                        'passes': len(sample['passes']), 'requests': len(requests), 'burst': len(burst),
                        'burstEnd': max(r['end'] for r in burst), 'laterStart': [round(r['start']) for r in sorted(later, key=lambda r: r['start'])],
                        'allEnd': max(r['end'] for r in requests),
                        'upstreamMedian': statistics.median(r['upstream'] for r in requests if r['upstream'] is not None),
                        'burstUpstream': sorted(r['upstream'] for r in burst if r['upstream'] is not None),
                        'bytes': sum(r['bytes'] for r in requests), 'options': sample['options'],
                        'unfiltered': [j['id'] for j in sample['unfilteredJourneys']],
                        'coverage': sorted(sample['realtimeCoverage'].values()), 'byKey': {r['key']: r for r in requests},
                        'raptor': sample['stages_ms'].get('raptor'), 'planning': sample['planningTime']})

print(f"{'run':22s} {'proc':8s} total  live  pass req burst burstEnd allEnd  ATPmed  later starts            options coverage")
for s in samples:
    cov = ''.join(c[0] for c in s['coverage'])
    print(f"{s['run']:22s} {str(s['process']):8s} {s['total']:5.0f} {s['realtime']:5.0f}  {s['passes']}   {s['requests']:2d}  {s['burst']:2d}   {s['burstEnd']:5.0f}  {s['allEnd']:5.0f}  {s['upstreamMedian']:5.0f}  {str(s['laterStart'])[:24]:24s} {len(s['options'])}/{len(s['unfiltered'])}  {cov}")

print()
for scenario in sorted({s['scenario'] for s in samples}):
    print(scenario)
    for arm in sorted({s['arm'] for s in samples}):
        rows = [s for s in samples if s['arm'] == arm and s['scenario'] == scenario]
        if not rows:
            continue
        med = lambda key: statistics.median(r[key] for r in rows)
        print(f"  {arm}: n={len(rows)} total med {med('total'):.0f} (min {min(r['total'] for r in rows):.0f}, max {max(r['total'] for r in rows):.0f})"
              f"  live med {med('realtime'):.0f}  burstEnd med {med('burstEnd'):.0f}  allEnd med {med('allEnd'):.0f}"
              f"  requests med {med('requests'):.0f}  bytes med {med('bytes') / 1e3:.0f} kB  ATP med {med('upstreamMedian'):.0f}  passes {sorted(r['passes'] for r in rows)}")
    # ATP wait of the boards asked by every sample of this scenario, per arm.
    rows = [s for s in samples if s['scenario'] == scenario]
    common = set.intersection(*[set(k for k, r in s['byKey'].items() if r['start'] < 50) for s in rows]) if rows else set()
    if common:
        print(f"  boards in the first burst of every sample: {len(common)}")
        for arm in sorted({s['arm'] for s in rows}):
            values = [statistics.median(s['byKey'][k]['upstream'] for k in common if s['byKey'][k]['upstream'] is not None) for s in rows if s['arm'] == arm]
            maxima = [max(s['byKey'][k]['upstream'] for k in common if s['byKey'][k]['upstream'] is not None) for s in rows if s['arm'] == arm]
            print(f"    {arm}: ATP wait on those boards, per-sample median {[round(v) for v in values]} -> median {statistics.median(values):.0f};"
                  f" per-sample max {[round(v) for v in maxima]} -> median {statistics.median(maxima):.0f}")
