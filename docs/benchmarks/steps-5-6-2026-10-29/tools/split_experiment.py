"""Live check of CAND-28b's mechanism: one wide Luxexpo board against the same lines split into
parallel requests. Sends exactly 6 requests per round through the relay (1 wide, 2 halves, 3 thirds)."""
import json, sys, time, datetime, concurrent.futures as cf, urllib.request
from urllib.parse import urlencode

RELAY = 'https://verkeier-api.pedrocordeiroo2.workers.dev/atp/departureBoard'
STOP = '000200417050'
WEIGHTS = {'6': 11, '25': 8, '7': 8, '455': 6, '21': 6, '403': 5, '502': 5, '201': 5, '456': 4, '211': 4, '507': 3,
           '324': 3, '326': 3, '212': 3, '325': 3, '323': 3, '501': 2, '304': 2, '305': 2, '322': 2, '407': 2, '811': 2,
           '327': 2, '812': 2, '406': 2, '222': 2, '321': 2, '303': 2, '311': 2, '301': 1, '401': 1, '309': 1, '405': 1}
LINES = sorted(WEIGHTS)

def groups(k):
    bins = [[] for _ in range(k)]; load = [0] * k
    for line in sorted(LINES, key=lambda l: -WEIGHTS[l]):
        i = load.index(min(load)); bins[i].append(line); load[i] += WEIGHTS[line]
    return [sorted(b) for b in bins]

def fetch(lines, date, hhmm):
    query = urlencode({'format': 'json', 'id': STOP, 'lang': 'en', 'date': date, 'time': hhmm, 'duration': 120,
                       'maxJourneys': -1, 'lines': ','.join(lines), 'rtMode': 'SERVER_DEFAULT', 'passlist': 1})
    request = urllib.request.Request(f'{RELAY}?{query}', headers={'Accept': 'application/json'})
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=30) as response:
        headers_at = time.monotonic()
        body = response.read()
        timing = response.headers.get('Server-Timing', '')
    ended = time.monotonic()
    upstream = next((float(p.split('dur=')[1].split(';')[0]) for p in timing.split(',') if 'upstream;dur=' in p), None)
    departures = json.loads(body).get('Departure') or []
    ids = sorted({(d.get('JourneyDetailRef') or {}).get('ref', '') + '|' + d.get('date', '') + d.get('time', '') for d in departures})
    return dict(lines=len(lines), wall=(ended - started) * 1000, headers=(headers_at - started) * 1000,
                upstream=upstream, bytes=len(body), departures=len(departures), ids=ids, started=started)

def run_variant(name, date, hhmm):
    parts = [LINES] if name == 'W' else groups(int(name[1]))
    t0 = time.monotonic()
    with cf.ThreadPoolExecutor(len(parts)) as pool:
        results = list(pool.map(lambda p: fetch(p, date, hhmm), parts))
    return dict(variant=name, elapsed=(time.monotonic() - t0) * 1000, parts=results,
                ids=sorted(set().union(*[r['ids'] for r in results])))

if __name__ == '__main__':
    rounds, out = int(sys.argv[1]), sys.argv[2]
    orders = [['W', 'S2', 'S3'], ['S3', 'W', 'S2'], ['S2', 'S3', 'W']]
    log = []
    for r in range(rounds):
        now = datetime.datetime.now()
        date, hhmm = now.strftime('%Y-%m-%d'), now.replace(minute=now.minute // 30 * 30).strftime('%H:%M:00')
        for name in orders[r % 3]:
            v = run_variant(name, date, hhmm); v.update(round=r, clock=now.strftime('%H:%M:%S'), time=hhmm)
            log.append(v)
            print(f"{now:%H:%M:%S} r{r} {name}: elapsed {v['elapsed']:6.0f} ms, upstream {[p['upstream'] for p in v['parts']]}, "
                  f"departures {sum(p['departures'] for p in v['parts'])}, ids {len(v['ids'])}", flush=True)
            time.sleep(2)
        time.sleep(5)
    for v in log:
        for p in v['parts']: p.pop('ids')
    json.dump(log, open(out, 'w'), indent=1)
