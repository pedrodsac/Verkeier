"""One row per recorded board request: width, size, ATP wait and transfer. Reads captures only."""
import json, sys, glob, os, statistics as st
from urllib.parse import urlparse, parse_qs

def rows(capture):
    out = []
    for meta in glob.glob(os.path.join(capture, 'network', '*.json')):
        if meta.endswith('.body.json'): continue
        m = json.load(open(meta))
        q = parse_qs(urlparse(m['url']).query)
        if 'departureBoard' not in m['url']: continue
        t = m.get('transport') or {}
        tr = (t.get('transactions') or [{}])[-1]
        up = None
        for part in (t.get('serverTiming') or '').split(','):
            part = part.strip()
            if part.startswith('upstream;dur='):
                up = float(part.split('dur=')[1].split(';')[0])
        if 'body' not in m: continue
        body = os.path.join(capture, 'network', m['body'])
        raw = os.path.getsize(body)
        try:
            deps = json.load(open(body)).get('Departure') or []
        except Exception:
            deps = []
        lines = q.get('lines', [''])[0]
        out.append(dict(capture=capture, stop=q['id'][0], lines=len(lines.split(',')) if lines else 0,
                        duration=int(q.get('duration', ['0'])[0]), departures=len(deps), bytes=raw,
                        wire=tr.get('encodedResponseBytes'), wait=tr.get('responseWaitMilliseconds'),
                        transfer=tr.get('transferMilliseconds'), upstream=up, start=t.get('taskStart'),
                        passlist=q.get('passlist', ['0'])[0]))
    return out

if __name__ == '__main__':
    allrows = []
    for c in sys.argv[1:]:
        allrows += rows(c)
    json.dump(allrows, sys.stdout)
