"""Per live sample: which board arrived last, by how much, and how wide the widest board was."""
import json, sys, os
boards = json.load(open(sys.argv[1]))
for cap in sorted(set(r['capture'] for r in boards)):
    rs = [r for r in boards if r['capture'] == cap]
    name = cap.split('Verkeier-captures/')[1]
    for s in json.load(open(os.path.join(cap, 'samples.json'))):
        t0 = s['operationStartReferenceSeconds']; t1 = t0 + s['total_ms'] / 1000
        sm = [r for r in rs if t0 - 0.05 <= r['start'] <= t1]
        if len(sm) < 2: print(f"{name:38s} {s['sample']} {len(sm)} boards"); continue
        for r in sm: r['end'] = r['start'] + (r['wait'] + r['transfer']) / 1000
        ends = sorted(sm, key=lambda r: r['end'])
        last, prev = ends[-1], ends[-2]
        wide = max(sm, key=lambda r: r['bytes'])
        rt = s['stages_ms'].get('realtime', 0)
        print(f"{name:38s} {s['sample']} tot {s['total_ms']:5.0f} n={len(sm):2d} last {last['stop']} {last['lines']:2d}l {last['bytes']/1e6:.2f}MB "
              f"[{(last['start']-t0)*1000:5.0f}→{(last['end']-t0)*1000:5.0f}] gap {(last['end']-prev['end'])*1000:4.0f} to {prev['stop']} {prev['lines']}l | "
              f"wide {wide['stop']} {wide['lines']}l {wide['bytes']/1e6:.2f}MB [{(wide['start']-t0)*1000:5.0f}→{(wide['end']-t0)*1000:5.0f}] up {wide['upstream'] or wide['wait']:.0f}")
