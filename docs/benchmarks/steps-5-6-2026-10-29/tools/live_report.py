"""Summarises the CAND-28b live A/B: per sample totals, passes, requests and the wide stop's timing."""
import json, sys, os, glob, statistics as st
from urllib.parse import urlparse, parse_qs
WIDE = {'000200417050', '000200417039', '000220402034'}
for run in sorted(glob.glob(os.path.join(sys.argv[1], '[0-9]-*'))):
    if run.endswith('.log') or not os.path.exists(os.path.join(run, 'samples.json')): continue
    transport = json.load(open(os.path.join(run, 'transport.json')))
    rows = []
    for m in transport:
        q = parse_qs(urlparse(m['url']).query)
        if 'departureBoard' not in m['url']: continue
        t = m['transport']; tr = t['transactions'][-1]
        up = next((float(p.split('dur=')[1].split(';')[0]) for p in (t.get('serverTiming') or '').split(',') if 'upstream;dur=' in p), None)
        rows.append(dict(stop=q['id'][0], lines=len(q.get('lines', [''])[0].split(',')) if q.get('lines') else 0,
                         start=t['taskStart'], end=t['taskStart'] + (tr['responseWaitMilliseconds'] + tr['transferMilliseconds']) / 1000,
                         up=up, net=tr['responseWaitMilliseconds'] + tr['transferMilliseconds']))
    for s in json.load(open(os.path.join(run, 'samples.json'))):
        t0 = s['operationStartReferenceSeconds']; t1 = t0 + s['total_ms'] / 1000
        sm = [r for r in rows if t0 - 0.05 <= r['start'] <= t1]
        wide = [r for r in sm if r['stop'] in WIDE and r['lines'] > 8]
        others = [r for r in sm if not (r['stop'] in WIDE and r['lines'] > 8)]
        last = max(sm, key=lambda r: r['end']) if sm else None
        wide_desc = ', '.join(f"{r['stop'][-5:]}:{r['lines']}l {r['net']:.0f}ms(up {r['up'] or 0:.0f}) end+{(r['end']-t0)*1000:.0f}" for r in sorted(wide, key=lambda r: (r['stop'], r['start'])))
        c = s['counters']
        print(f"{os.path.basename(run):22s} s{s['sample']} total {s['total_ms']:5.0f} rt {s['stages_ms'].get('realtime',0):5.0f} passes {len(s['passes'])} "
              f"req {c['networkRequests']:3d} bytes {c['responseBytes']/1e6:.2f}MB others med {st.median([r['net'] for r in others]):.0f}ms(up {st.median([r['up'] for r in others if r['up'] is not None] or [0]):.0f}) "
              f"last {last['stop'][-5:]}:{last['lines']}l end+{(last['end']-t0)*1000:.0f} | wide {wide_desc}")
