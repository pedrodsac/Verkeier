"""Compare every trimmed arm with the original replay, and the original with its live capture.

usage: python3 -I compare_arms.py <passlist-dir> [--runs runs-dir-name] [--json out.json]

Runs are <dir>/runs/<capture>-<arm>-<rep>. A sample is result-identical when every RESULT field matches.
Counters are reported separately: fewer passlist stops lower predictedEvents by design.
"""
import json, pathlib, re, sys
from collections import defaultdict

RESULT = ["unfilteredJourneys", "journeys", "options", "recommendedOption", "realtimeCoverage",
          "matchingRejections", "displayedLegs", "supplementalOptions", "canLoadEarlier", "canLoadLater"]


def load(path):
    p = path / "samples.json"
    return json.load(open(p)) if p.exists() else None


def strip(i):
    return re.sub(r"^g\d+:", "", i)


def leg_detail(a, b):
    """Summarise displayedLegs differences: time shifts and source changes."""
    out = []
    key = lambda l: (l.get("option"), l.get("trip"), l.get("stop"))
    A, B = {key(l): l for l in a or []}, {key(l): l for l in b or []}
    if set(A) != set(B):
        out.append(f"legs only-orig {len(set(A) - set(B))} only-arm {len(set(B) - set(A))}")
    for k in sorted(set(A) & set(B), key=str):
        x, y = A[k], B[k]
        for f in sorted(set(x) | set(y)):
            if x.get(f) != y.get(f):
                if isinstance(x.get(f), (int, float)) and isinstance(y.get(f), (int, float)):
                    out.append(f"{x.get('line')}@{k[2]} {f} {y[f] - x[f]:+.0f}s")
                else:
                    out.append(f"{x.get('line')}@{k[2]} {f} {x.get(f)}->{y.get(f)}")
    return out


def main():
    root = pathlib.Path(sys.argv[1])
    runs = defaultdict(dict)
    runs_name = sys.argv[sys.argv.index("--runs") + 1] if "--runs" in sys.argv else "runs"
    for d in sorted((root / runs_name).iterdir()):
        # "real" arms run the engine change itself (no experiment flags); origreal is it on full passlists.
        m = re.fullmatch(r"(.+)-(orig(?:real)?|[kf]\d+(?:last)?(?:fix|gap|real)?|finf)-(\d+)", d.name)
        if m and load(d) is not None:
            runs[(m[1], int(m[3]))][m[2]] = d
    report = []
    tally = defaultdict(lambda: [0, 0])
    for (name, rep), arms in sorted(runs.items()):
        if "orig" not in arms:
            continue
        base = load(arms["orig"])
        live = load(root / "captures-orig" / name)
        for i, x in enumerate(base):
            if live and i < len(live):
                same = [strip(j["id"]) for j in x["unfilteredJourneys"]] == [strip(j["id"]) for j in live[i]["unfilteredJourneys"]]
                print(f"{name:8s} r{rep} s{i} orig vs live journeys: {'same' if same else 'DIFFER'}")
            for arm in sorted(a for a in arms if a != "orig"):
                y = load(arms[arm])[i]
                diffs = [f for f in RESULT if x.get(f) != y.get(f)]
                counters = {k: (x["counters"].get(k), y["counters"].get(k)) for k in sorted(set(x["counters"]) | set(y["counters"]))
                            if x["counters"].get(k) != y["counters"].get(k) and k != "responseBytes"}
                detail = []
                if "unfilteredJourneys" in diffs:
                    xa = [strip(j["id"]) for j in x["unfilteredJourneys"]]
                    ya = [strip(j["id"]) for j in y["unfilteredJourneys"]]
                    detail.append(f"journeys lost {len(set(xa) - set(ya))} gained {len(set(ya) - set(xa))}")
                if "displayedLegs" in diffs:
                    detail += leg_detail(x.get("displayedLegs"), y.get("displayedLegs"))[:8]
                if "realtimeCoverage" in diffs:
                    rc = {k: (x["realtimeCoverage"].get(k), y["realtimeCoverage"].get(k))
                          for k in set(x["realtimeCoverage"]) | set(y["realtimeCoverage"])
                          if x["realtimeCoverage"].get(k) != y["realtimeCoverage"].get(k)}
                    detail.append(f"coverage {list(rc.values())[:4]}")
                tally[arm][0] += not diffs
                tally[arm][1] += 1
                row = {"capture": name, "rep": rep, "sample": i, "arm": arm, "identical": not diffs, "differences": diffs,
                       "detail": detail, "counters": counters,
                       "bytes": [x["counters"]["responseBytes"], y["counters"]["responseBytes"]],
                       "total": [x["total_ms"], y["total_ms"]]}
                report.append(row)
                print(f"   {arm:5s} {'IDENTICAL' if not diffs else 'DIFFERS ' + ','.join(diffs)}"
                      f"  MB {row['bytes'][0]/1e6:.1f}->{row['bytes'][1]/1e6:.1f}"
                      f"  total {row['total'][0]:.0f}->{row['total'][1]:.0f}"
                      + (f"\n         {detail}" if detail else ""))
    print()
    for arm, (same, n) in sorted(tally.items()):
        print(f"{arm}: {same} of {n} samples result-identical")
    if "--json" in sys.argv:
        pathlib.Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
