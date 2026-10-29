"""Pairs replays of two variants on the same capture and reports result identity.

usage: python3 -I compare_arms.py <runs-dir> <left-label> <right-label> [--json out.json]
Run folders are <capture>-<label>-<rep>. Identity means every result field, the pass and warm-up pass counts,
the board arrival order and every counter except responseBytes and networkRequests match in every sample.
Request and byte counts are reported separately, because a split board is more requests for the same rows.
"""
import json, pathlib, re, statistics, sys

RESULT = ["unfilteredJourneys", "journeys", "options", "recommendedOption", "realtimeCoverage",
          "matchingRejections", "displayedLegs", "supplementalOptions", "canLoadEarlier", "canLoadLater"]
SKIP = {"responseBytes", "networkRequests"}

def load(path):
    p = path / "samples.json"
    return json.load(open(p)) if p.exists() else None

def differences(a, b):
    out = [f for f in RESULT if a.get(f) != b.get(f)]
    if len(a["passes"]) != len(b["passes"]): out.append(f"passes {len(a['passes'])}->{len(b['passes'])}")
    if len(a.get("warmUpPasses", [])) != len(b.get("warmUpPasses", [])): out.append("warmUpPasses")
    stops = lambda s: [r["stop"] for r in s.get("realtimeBoards", [])]
    if sorted(set(stops(a))) != sorted(set(stops(b))): out.append("realtimeBoards set")
    elif stops(a) != stops(b): out.append("realtimeBoards order")
    for k in sorted(set(a["counters"]) | set(b["counters"])):
        if k not in SKIP and a["counters"].get(k) != b["counters"].get(k):
            out.append(f"counter {k} {a['counters'].get(k)}->{b['counters'].get(k)}")
    return out

def main():
    runs, left, right = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    pairs = {}
    for d in sorted(runs.iterdir()):
        m = re.fullmatch(r"(.+)-([A-Za-z0-9x-]+?)-(\d+)", d.name)
        if m and m[2] in (left, right) and load(d) is not None:
            pairs.setdefault((m[1], int(m[3])), {})[m[2]] = d
    report = []
    for (name, rep), arms in sorted(pairs.items()):
        if set(arms) != {left, right}:
            print(f"{name} rep {rep}: incomplete pair {sorted(arms)}"); continue
        a, b = load(arms[left]), load(arms[right])
        approx = [json.load(open(arms[k] / "approximate-queries.json")) if (arms[k] / "approximate-queries.json").exists() else None for k in (left, right)]
        for x, y in zip(a, b):
            d = differences(x, y)
            row = dict(capture=name, rep=rep, sample=x["process"], identical=not d, differences=d,
                       requests=[x["counters"]["networkRequests"], y["counters"]["networkRequests"]],
                       bytes=[x["counters"]["responseBytes"], y["counters"]["responseBytes"]],
                       totals=[x["total_ms"], y["total_ms"]], realtime=[x["stages_ms"].get("realtime"), y["stages_ms"].get("realtime")],
                       passes=[len(x["passes"]), len(y["passes"])],
                       approximated=[len(q) if isinstance(q, list) else (None if q is None else len(q.get("queries", q))) for q in approx])
            report.append(row)
            print(f"{name:8s} r{rep} {x['process']:8s} {'IDENTICAL' if not d else 'DIFFERS ' + str(d)}  passes {row['passes']}"
                  f"  requests {row['requests']}  MB {x['counters']['responseBytes']/1e6:.2f}/{y['counters']['responseBytes']/1e6:.2f}"
                  f"  total {x['total_ms']:.0f}/{y['total_ms']:.0f}  approximated {row['approximated']}")
    if report:
        print(f"\n{sum(r['identical'] for r in report)} of {len(report)} samples identical")
    if "--json" in sys.argv:
        pathlib.Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
