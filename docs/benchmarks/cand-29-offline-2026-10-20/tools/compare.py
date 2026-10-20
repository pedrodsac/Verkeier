"""Compare replay result dirs. usage: compare.py <control-dir> <candidate-dir> [--json]

Reads samples.json (and approximate-queries.json / optimisation.json when present). Prints one line per sample and the
differences in the engine's result fields."""
import json, sys, pathlib, datetime

FIELDS = ["unfilteredJourneys", "journeys", "options", "recommendedOption", "realtimeCoverage", "matchingRejections"]
COUNTERS = ["networkRequests", "responseBytes", "boardCacheHits", "boardsCovered", "incompleteBoards", "candidates",
            "retainedAlternatives", "invalidJourneys", "walkingRequests"]


def load(path):
    p = pathlib.Path(path)
    samples = json.load(open(p / "samples.json"))
    approx = []
    ap = p / "approximate-queries.json"
    if ap.exists():
        approx = json.load(open(ap))
    canary = None
    op = p / "optimisation.json"
    if op.exists():
        canary = json.load(open(op)).get("build_ms")
    return samples, approx, canary


def hhmm(v):
    return datetime.datetime.fromtimestamp(v).strftime("%H:%M:%S")


def jsig(j):
    return (j["id"], round(j["departure"], 1), round(j["arrival"], 1))


def summary(sample):
    return {
        "process": sample["process"], "total_ms": sample["total_ms"], "passes": len(sample["passes"]),
        **{k: sample["counters"].get(k) for k in COUNTERS},
    }


def diff(a, b):
    out = []
    for f in FIELDS:
        if a.get(f) != b.get(f):
            out.append(f)
    ca, cb = a["counters"], b["counters"]
    for k in COUNTERS:
        if ca.get(k) != cb.get(k):
            out.append(f"counter:{k} {ca.get(k)}->{cb.get(k)}")
    return out


def main():
    ctl, cand = sys.argv[1], sys.argv[2]
    sa, aa, ca = load(ctl)
    sb, ab, cb = load(cand)
    print(f"control   {ctl}  canary {ca and round(ca)}  approximate queries {len(aa)}")
    print(f"candidate {cand}  canary {cb and round(cb)}  approximate queries {len(ab)}")
    for i, (x, y) in enumerate(zip(sa, sb)):
        d = diff(x, y)
        print(f"  [{i}] {x['process']:8s} passes {len(x['passes'])}->{len(y['passes'])}  total {x['total_ms']:.0f}->{y['total_ms']:.0f} ms"
              f"  req {x['counters'].get('networkRequests')}->{y['counters'].get('networkRequests')}"
              f"  bytes {x['counters'].get('responseBytes')}->{y['counters'].get('responseBytes')}"
              f"  boards {x['counters'].get('boardsCovered')}->{y['counters'].get('boardsCovered')}"
              f"  differs: {d if d else 'none'}")
        if "unfilteredJourneys" in d:
            ja = {jsig(j) for j in x["unfilteredJourneys"]}
            jb = {jsig(j) for j in y["unfilteredJourneys"]}
            print("      only control:", sorted(ja - jb))
            print("      only candidate:", sorted(jb - ja))


if __name__ == "__main__":
    main()
