"""How well do simple rules predict ATP's own prognoses for the stops a terminus-kept cap leaves out?

usage: python3 -I gap_estimate_check.py <captures-orig-dir> [K] [--unique]

For every recorded passlist longer than K (default 10), the capped passlist keeps stops 0..K-2 and the last
stop; stops K-1..n-2 are the gap. Works in ATP's own minute times. For each gap stop time that ATP reports
(arrival and departure), compares ATP's realtime with:
  constant  the scheduled time plus the delay at stop K-2 (the last kept stop before the gap)
  linear    the delay interpolated by scheduled time between stop K-2 and the terminus
Also counts gap stop times more than 30 minutes after stop K-2 whose carried delay is not zero (where the
engine's 30-minute horizon falls back to the timetable). --unique counts each passlist once (same trip,
board stop and stop times), since captures repeat boards.
"""
import datetime as dt, json, pathlib, sys
from collections import Counter


def L(v):
    return v if isinstance(v, list) else [v]


def at(date, time):
    return dt.datetime.fromisoformat(f"{date}T{time}") if date and time else None


def pair(stop, kind):
    """(scheduled, realtime) for kind 'arr' or 'dep'; realtime None when ATP gives none."""
    scheduled = at(stop.get(f"{kind}Date"), stop.get(f"{kind}Time"))
    big = kind.capitalize()
    realtime = at(stop.get(f"rt{big}Date") or stop.get(f"{kind}Date"), stop.get(f"rt{big}Time"))
    return scheduled, realtime


def delay(stop):
    for kind in ("dep", "arr"):
        scheduled, realtime = pair(stop, kind)
        if scheduled and realtime:
            return (realtime - scheduled).total_seconds(), scheduled
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root, k = pathlib.Path(args[0]), int(args[1]) if len(args) > 1 else 10
    unique, seen = "--unique" in sys.argv, set()
    c = Counter()
    for body in sorted(root.glob("*/network/*.body.json")):
        for departure in L(json.loads(body.read_bytes()).get("Departure", [])):
            rows = L(departure.get("Stops", {}).get("Stop", []))
            if len(rows) <= k:
                continue
            if unique:
                key = json.dumps([departure.get("JourneyDetailRef"), rows], sort_keys=True)
                if key in seen:
                    continue
                seen.add(key)
            c["passlists"] += 1
            anchor, terminus = delay(rows[k - 2]), delay(rows[-1])
            if anchor is None:
                c["passlistsWithoutAnchorDelay"] += 1
                continue
            for stop in rows[k - 1:-1]:
                for kind in ("arr", "dep"):
                    scheduled, realtime = pair(stop, kind)
                    if not scheduled or not realtime:
                        continue
                    c["gapTimes"] += 1
                    constant = scheduled + dt.timedelta(seconds=anchor[0])
                    c["constantMatches"] += constant == realtime
                    if terminus and terminus[1] > anchor[1]:
                        share = (scheduled - anchor[1]) / (terminus[1] - anchor[1])
                        linear = scheduled + dt.timedelta(seconds=anchor[0] + share * (terminus[0] - anchor[0]))
                        c["linearMatches"] += abs((linear - realtime).total_seconds()) < 30
                    if (scheduled - anchor[1]).total_seconds() > 30 * 60 and anchor[0] != 0:
                        c["beyond30MinNonzeroDelay"] += 1
    c["constantShare"] = round(100 * c["constantMatches"] / c["gapTimes"], 1)
    c["linearShare"] = round(100 * c["linearMatches"] / c["gapTimes"], 1)
    print(json.dumps(dict(c), indent=1))


if __name__ == "__main__":
    main()
