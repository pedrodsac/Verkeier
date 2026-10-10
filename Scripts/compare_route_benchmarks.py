#!/usr/bin/env python3
"""Compare paired benchmark outputs without treating timings as route evidence."""
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline', type=Path)
parser.add_argument('optimized', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

def samples(folder):
    result = {}
    paths = [folder / 'samples.json'] if (folder / 'samples.json').exists() else folder.glob('*/samples.json')
    for path in paths:
        for value in json.loads(path.read_text()):
            key = (value['scenario'], value['process'])
            result.setdefault(key, []).append(value)
    return result

before, after = samples(args.baseline), samples(args.optimized)
fields = ['planningTime', 'avoidTightTransfers', 'modePreference', 'recommendedOption', 'options', 'unfilteredJourneys',
          'journeys', 'displayedLegs', 'realtimeCoverage', 'refreshPolicy', 'canonicalPlans',
          'canonicalSupplementalPlans', 'matchingRejections',
          'canLoadEarlier', 'canLoadLater', 'supplementalOptions']
if not before or not after:
    raise SystemExit('Both inputs must contain benchmark samples')
report = []
errors = []
for key in sorted(before.keys() | after.keys()):
    left, right = before.get(key, []), after.get(key, [])
    if len(left) != len(right):
        errors.append({'scenario': key, 'count': [len(left), len(right)]})
        continue
    compared = [field for field in fields if all(field in value for value in left + right)]
    for index, (a, b) in enumerate(zip(left, right)):
        for field in compared:
            if a[field] != b[field]:
                errors.append({'scenario': key, 'sample': index, 'field': field})
    a_ms = statistics.median(value['total_ms'] for value in left)
    b_ms = statistics.median(value['total_ms'] for value in right)
    report.append({'scenario': key[0], 'process': key[1], 'samples': len(left),
        'before_ms': a_ms, 'after_ms': b_ms, 'change_percent': (b_ms / a_ms - 1) * 100,
        'before_memory_bytes': statistics.median(value['peak_memory_bytes'] for value in left),
        'after_memory_bytes': statistics.median(value['peak_memory_bytes'] for value in right),
        'compared_fields': compared,
        'unavailable_fields': [field for field in fields if field not in compared]})
args.output.write_text(json.dumps({'comparisons': report, 'differences': errors}, indent=2))
for row in report:
    print(f'{row["scenario"]:18} {row["process"]:7} {row["before_ms"]:7.0f} → {row["after_ms"]:7.0f} ms ({row["change_percent"]:+.1f}%)')
if errors:
    raise SystemExit(f'{len(errors)} equivalence differences; see {args.output}')
print('All available route fields match. See the report for fields absent from older harnesses.')
