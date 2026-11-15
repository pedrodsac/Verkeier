"""Count board rows whose patch would stop being chronological once their passlist is capped at K stops.

usage: python3 -I chronology_check.py <captures-dir> [K ...]

Mirrors the estimate rule in MobilitéitKit a152c0f (HafasRealtimeRoutingProvider+Events.swift, patch(for:)):
after the last reported stop, a stop gets that stop's delay for 30 minutes of scheduled time (if the delay is
at most 2 h), then its scheduled time. A delayed trip that runs on past that horizon can fall back in time,
and the engine then drops the whole patch (invalidTripTimeline). Counts every row, matched or not.
"""
import datetime, glob, json, pathlib, sys


def minutes(date, time):
    if not date or not time:
        return None
    return datetime.datetime.fromisoformat(f"{date}T{time}").timestamp() / 60


def as_list(value):
    return value if isinstance(value, list) else [value]


def risky(stops, k):
    report = None
    for stop in stops[:k]:
        rt = stop.get("rtDepTime") or stop.get("rtArrTime")
        if rt:
            scheduled = minutes(stop.get("depDate") or stop.get("arrDate"), stop.get("depTime") or stop.get("arrTime"))
            actual = minutes(stop.get("rtDepDate") or stop.get("rtArrDate") or stop.get("depDate") or stop.get("arrDate"), rt)
            if scheduled is not None and actual is not None:
                report = (scheduled, actual - scheduled)
    if report is None:
        return False
    anchor, delay = report
    previous = None
    for stop in stops[k:]:
        scheduled = minutes(stop.get("arrDate") or stop.get("depDate"), stop.get("arrTime") or stop.get("depTime"))
        if scheduled is None:
            continue
        estimate = scheduled + delay if 0 <= scheduled - anchor <= 30 and abs(delay) <= 120 else scheduled
        if previous is not None and estimate < previous - 1e-6:
            return True
        previous = estimate
    return False


def main():
    root = pathlib.Path(sys.argv[1])
    ks = [int(v) for v in sys.argv[2:]] or [5, 10, 20]
    for capture in sorted(p for p in root.iterdir() if (p / "network").is_dir()):
        counts = dict.fromkeys(ks, 0)
        for body in glob.glob(str(capture / "network" / "*.body.json")):
            for row in as_list(json.load(open(body)).get("Departure", [])):
                stops = (row.get("Stops") or {}).get("Stop")
                if not stops:
                    continue
                stops = as_list(stops)
                for k in ks:
                    counts[k] += len(stops) > k and risky(stops, k)
        print(capture.name, " ".join(f"K{k}={n}" for k, n in counts.items()))


if __name__ == "__main__":
    main()
