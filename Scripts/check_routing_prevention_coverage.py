#!/usr/bin/env python3
"""Check that each routing checklist case points to existing named tests.

This verifies traceability only. Run the Swift Testing suites separately to
establish that the referenced assertions pass.
"""
import argparse
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--package', type=Path, default=root.parent / 'MobilitéitKit',
                    help='The existing MobiliteitKit checkout')
args = parser.parse_args()
roots = [args.package / 'Tests', root / 'VerkéierTests']
for directory in roots:
    if not directory.is_dir():
        parser.error(f'Test directory does not exist: {directory}')

# Swift Testing permits attributes with argument lists on preceding lines.
# Test function names in this project start with a lowercase letter.
tests = set()
for directory in roots:
    for path in directory.rglob('*.swift'):
        for declaration in re.findall(r'@Test\b(?:(?!@Test\b).)*?\bfunc\s+(\w+)\s*\(',
                                      path.read_text(), flags=re.S):
            tests.add(declaration)

plan = root / 'docs/ROUTING_FAILURE_PREVENTION_IMPLEMENTATION.md'
rows = re.findall(r'^\| (\d\d) \| (.+) \|$', plan.read_text(), flags=re.M)
errors = []
ids = [int(case) for case, _ in rows]
if sorted(ids) != list(range(1, 50)):
    errors.append('Expected each case 01–49 exactly once.')
references = set()
for case, body in rows:
    named = [word for word in re.findall(r'\b[a-z][A-Za-z0-9]+\b', body)
             if any(letter.isupper() for letter in word)]
    if not named:
        errors.append(f'Case {case} has no named regression.')
    for name in named:
        references.add(name)
        if name not in tests:
            errors.append(f'Case {case} references missing @Test function: {name}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'49 cases reference {len(references)} existing @Test functions. '
      'Run the suites to verify behavior.')
