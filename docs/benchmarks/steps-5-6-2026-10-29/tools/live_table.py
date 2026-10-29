"""One row per live A/B sample: total, realtime stage, passes, requests, and the Luxexpo board (slowest part)
against the median of the sample's other boards. Network time is server wait plus transfer."""
import json, sys, os, glob, statistics as st
from urllib.parse import urlparse, parse_qs
LUX = '000200417050'
print('| Run | Arm | Sample | Total, ms | Realtime stage, ms | Passes | Requests | Other boards, median ms | Luxexpo, ms | Luxexpo / others | Realtime / others |')
print('|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|')
ratios = {}
for run in sorted(glob.glob(os.path.join(sys.argv[1], '[0-9]-*'))):
    if run.endswith('.log'): continue
    arm = os.path.basename(run).split('-')[1]
    rows = []
    for m in json.load(open(os.path.join(run, 'transport.json'))):
        if 'departureBoard' not in m['url']: continue
        q = parse_qs(urlparse(m['url']).query); t = m['transport']; tr = t['transactions'][-1]
        rows.append(dict(stop=q['id'][0], start=t['taskStart'], net=tr['responseWaitMilliseconds'] + tr['transferMilliseconds']))
    for s in json.load(open(os.path.join(run, 'samples.json'))):
        t0 = s['operationStartReferenceSeconds']; t1 = t0 + s['total_ms'] / 1000
        sm = [r for r in rows if t0 - 0.05 <= r['start'] <= t1]
        others = st.median(r['net'] for r in sm if r['stop'] != LUX)
        lux = max(r['net'] for r in sm if r['stop'] == LUX)
        rt = s['stages_ms'].get('realtime', 0)
        ratios.setdefault(arm, []).append((lux / others, rt / others, len(s['passes'])))
        print(f"| {os.path.basename(run)} | {arm} | {s['process']} | {s['total_ms']:,.0f} | {rt:,.0f} | {len(s['passes'])} | {s['counters']['networkRequests']} | "
              f"{others:,.0f} | {lux:,.0f} | {lux/others:.2f} | {rt/others:.2f} |")
for arm, v in sorted(ratios.items()):
    print(f"\n{arm}: Luxexpo/others median {st.median(x[0] for x in v):.2f} (range {min(x[0] for x in v):.2f}-{max(x[0] for x in v):.2f}); "
          f"realtime/others median {st.median(x[1] for x in v):.2f}; one-pass samples {sum(x[2] == 1 for x in v)} of {len(v)}")
