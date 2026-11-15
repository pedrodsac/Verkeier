#!/usr/bin/env python3
"""Which recorded departure boards covered the rides of the journeys a search produced?

Read-only: recorded capture folders plus the installed timetable. No network.
Usage: board_value.py <gtfs.sqlite> <out.json> <capture dir>...
"""
import json, math, re, sqlite3, sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from zoneinfo import ZoneInfo

TZ = ZoneInfo('Europe/Luxembourg')
WINDOW = 90  # seconds, the engine's matching window


def norm_stop(value):
    return str(value).zfill(12)


class Feed:
    def __init__(self, path):
        self.db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
        self.trips = {}
        self.stops = {row[0]: (row[1], row[2] / 1e6, row[3] / 1e6) for row in
                      self.db.execute('select gtfs_id, name, lat_e6, lon_e6 from stop')}

    def trip(self, gtfs_id):
        if gtfs_id not in self.trips:
            line = self.db.execute('select r.short_name from trip t join route r on r.id = t.route_id '
                                   'where t.gtfs_id = ?', (gtfs_id,)).fetchone()
            times = self.db.execute(
                'select s.gtfs_id, st.arrival_sec, st.departure_sec from stop_time st '
                'join trip t on t.id = st.trip_id join stop s on s.id = st.stop_id '
                'where t.gtfs_id = ? order by st.sequence', (gtfs_id,)).fetchall()
            self.trips[gtfs_id] = (line[0] if line else None, times)
        return self.trips[gtfs_id]

    def distance(self, a, b):
        (_, la, lo), (_, lb, lp) = self.stops[a], self.stops[b]
        p, q = math.radians(la), math.radians(lb)
        x = math.sin((q - p) / 2) ** 2 + math.cos(p) * math.cos(q) * math.sin(math.radians(lp - lo) / 2) ** 2
        return 6_371_000 * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x))


def service_time(date, seconds):
    day = datetime.strptime(date, '%Y%m%d').replace(tzinfo=TZ)
    return (day.replace(hour=12) - timedelta(hours=12) + timedelta(seconds=seconds)).timestamp()


def local_time(date, time):
    if not date or not time:
        return None
    return datetime.strptime(f'{date} {time}', '%Y-%m-%d %H:%M:%S').replace(tzinfo=TZ).timestamp()


def rides_of(journey_id, feed):
    rides = []
    for part in journey_id.split(':', 2)[2].split('|'):
        match = re.fullmatch(r'(.+)@(\d{8}):(\d+)-(\d+)', part)
        if not match:
            continue
        trip, date, board, alight = match[1], match[2], int(match[3]), int(match[4])
        line, times = feed.trip(trip)
        if not times or alight >= len(times):
            continue
        rides.append({'trip': trip, 'date': date, 'line': line,
                      'board': times[board][0], 'alight': times[alight][0],
                      'departure': service_time(date, times[board][2] if times[board][2] is not None else times[board][1]),
                      'arrival': service_time(date, times[alight][1] if times[alight][1] is not None else times[alight][2])})
    return rides


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def rows_of(body):
    departures = body.get('Departure') or (body.get('DepartureBoard') or {}).get('Departure')
    rows = []
    for row in as_list(departures):
        product = as_list(row.get('ProductAtStop') or row.get('Product'))
        line = (product[0].get('line') or product[0].get('displayNumber')) if product else None
        stops = []
        for stop in as_list((row.get('Stops') or {}).get('Stop')):
            mast = (stop.get('mainMast') or {}).get('extId') or stop.get('mainMastExtId') or stop.get('extId')
            stops.append({'stop': norm_stop(mast),
                          'dep': local_time(stop.get('depDate'), stop.get('depTime')),
                          'arr': local_time(stop.get('arrDate'), stop.get('arrTime')),
                          'rtDep': stop.get('rtDepTime') is not None, 'rtArr': stop.get('rtArrTime') is not None,
                          'cancelled': bool(stop.get('cancelled') or stop.get('cancelledDeparture'))})
        rows.append({'line': str(line).strip() if line is not None else None, 'stops': stops,
                     'live': row.get('rtTime') is not None or any(s['rtDep'] or s['rtArr'] for s in stops),
                     'cancelled': bool(row.get('cancelled'))})
    return rows


def cover(ride, rows):
    """How one board covers one ride: None, or which events it has and whether they are reported live."""
    best = None
    for row in rows:
        if row['line'] is None or ride['line'] is None or row['line'].lower() != str(ride['line']).lower():
            continue
        for index, stop in enumerate(row['stops']):
            if stop['stop'] != ride['board'] or stop['dep'] is None or abs(stop['dep'] - ride['departure']) > WINDOW:
                continue
            upstream_live = any(s['rtDep'] or s['rtArr'] for s in row['stops'][:index + 1])
            alight = next((s for s in row['stops'][index + 1:] if s['stop'] == ride['alight']
                           and s['arr'] is not None and abs(s['arr'] - ride['arrival']) <= WINDOW), None)
            found = {'boardReported': stop['rtDep'], 'boardLive': upstream_live,
                     'alight': alight is not None, 'alightReported': bool(alight and alight['rtArr'])}
            score = (found['boardLive'], found['boardReported'], found['alight'], found['alightReported'])
            if best is None or score > best[0]:
                best = (score, found)
    return best[1] if best else None


def analyse(directory, feed):
    directory = Path(directory)
    samples = json.loads((directory / 'samples.json').read_text())
    bodies = {}
    for meta_path in (directory / 'network').glob('*.json'):
        if meta_path.name.endswith('.body.json'):
            continue
        meta = json.loads(meta_path.read_text())
        bodies[round(meta['transport']['taskStart'], 4)] = directory / 'network' / meta['body']
    results = []
    for index, sample in enumerate(samples):
        shown = set(sample['options'])
        journeys = [j['id'] for j in sample['unfilteredJourneys']]
        rides = {}
        for journey in journeys:
            for ride in rides_of(journey, feed):
                key = (ride['trip'], ride['date'], ride['board'], ride['alight'])
                entry = rides.setdefault(key, {**ride, 'shown': False, 'journeys': []})
                entry['shown'] |= journey in shown
                entry['journeys'].append(journey)
        if not rides:
            continue
        shown_rides = [r for r in rides.values() if r['shown']]
        reference = rides_of(next(j for j in journeys if j in shown), feed)
        origin, destination = reference[0]['board'], reference[-1]['alight']
        first = min(t['metrics']['taskStart'] for t in sample['transport'])
        boards = []
        for request in sample['transport']:
            metrics = request['metrics']
            query = parse_qs(urlparse(request['request']).query)
            stop = norm_stop(query['id'][0])
            body_path = bodies.get(round(metrics['taskStart'], 4))
            rows = rows_of(json.loads(body_path.read_text())) if body_path and body_path.exists() else None
            upstream = re.search(r'upstream;dur=([\d.]+)', metrics.get('serverTiming') or '')
            board = {'stop': stop, 'name': feed.stops.get(stop, ('?',))[0],
                     'lines': len(query['lines'][0].split(',')) if 'lines' in query else 0,
                     'start': (metrics['taskStart'] - first) * 1000, 'end': (metrics['taskEnd'] - first) * 1000,
                     'upstream': float(upstream[1]) if upstream else None,
                     'bytes': sum(t.get('encodedResponseBytes', 0) for t in metrics['transactions']),
                     'rows': len(rows) if rows is not None else None,
                     'liveRows': sum(r['live'] for r in rows) if rows is not None else None,
                     'toOrigin': feed.distance(stop, origin) if stop in feed.stops else None,
                     'toDestination': feed.distance(stop, destination) if stop in feed.stops else None,
                     'covers': []}
            if rows is not None:
                for key, ride in rides.items():
                    found = cover(ride, rows)
                    if found:
                        board['covers'].append({'ride': '|'.join(key), 'shown': ride['shown'], **found})
            boards.append(board)
        providers = defaultdict(list)
        for position, board in enumerate(boards):
            for item in board['covers']:
                if item['boardLive']:
                    providers[item['ride']].append(position)
        results.append({'capture': str(directory), 'sample': index, 'scenario': sample['scenario'],
                        'total': sample['total_ms'], 'realtime': sample['stages_ms'].get('realtime'),
                        'coverage': sample.get('realtimeCoverage'),
                        'rides': [{'ride': '|'.join(k), 'line': r['line'], 'shown': r['shown'],
                                   'board': feed.stops[r['board']][0], 'alight': feed.stops[r['alight']][0],
                                   'providers': providers.get('|'.join(k), [])} for k, r in rides.items()],
                        'boards': boards, 'missingBodies': sum(b['rows'] is None for b in boards)})
    return results


if __name__ == '__main__':
    feed = Feed(sys.argv[1])
    output = []
    for directory in sys.argv[3:]:
        output += analyse(directory, feed)
    Path(sys.argv[2]).write_text(json.dumps(output, indent=1))
    print(len(output), 'samples')
