"""Compare original and trimmed replays, and each against its live capture.

usage: python3 -I compare.py <runs-dir> [--json out.json]

Pairs <name>-orig-<rep> with <name>-trim-<rep>. A pair is identical when every result field and every counter
except responseBytes match in every sample. Also checks that the original replay reproduces the live capture's
engine journeys and request counts.
"""
import json, pathlib, re, statistics, sys

RESULT = ["unfilteredJourneys", "journeys", "options", "recommendedOption", "realtimeCoverage",
          "matchingRejections", "displayedLegs", "supplementalOptions", "canLoadEarlier", "canLoadLater"]
TIMING = ["decode", "providerBoardPreparation", "boardMatching", "providerStopMatching", "realtime"]
CAPTURES = pathlib.Path.home() / "Developer/Verkeier-captures"
LIVE = {"st-L1": "server-timing-2026-10-20/L1", "s7-L1": "step7-2026-10-20/L1", "s7-L2": "step7-2026-10-20/L2",
        "s7-L3": "step7-2026-10-20/L3", "c28-now": "cand-28-live-2026-10-19/live-now",
        "c28-rev": "cand-28-live-2026-10-19/live-reverse", "c28-esch": "cand-28-live-2026-10-19/live-esch",
        "st22-L2": "server-timing-2026-10-22/L2"}


def load(path):
    p = path / "samples.json"
    return json.load(open(p)) if p.exists() else None


def differences(a, b, skip_bytes=True):
    out = [f for f in RESULT if a.get(f) != b.get(f)]
    if len(a["passes"]) != len(b["passes"]):
        out.append(f"passes {len(a['passes'])}->{len(b['passes'])}")
    if len(a.get("warmUpPasses", [])) != len(b.get("warmUpPasses", [])):
        out.append("warmUpPasses")
    if [r["stop"] for r in a.get("realtimeBoards", [])] != [r["stop"] for r in b.get("realtimeBoards", [])]:
        out.append("realtimeBoards order")
    for k in sorted(set(a["counters"]) | set(b["counters"])):
        if skip_bytes and k == "responseBytes":
            continue
        if a["counters"].get(k) != b["counters"].get(k):
            out.append(f"counter {k} {a['counters'].get(k)}->{b['counters'].get(k)}")
    return out


def main():
    runs = pathlib.Path(sys.argv[1])
    pairs = {}
    for d in sorted(runs.iterdir()):
        m = re.fullmatch(r"(.+)-(orig|trim)-(\d+)", d.name)
        if m and load(d) is not None:
            pairs.setdefault((m[1], int(m[3])), {})[m[2]] = d
    report = []
    for (name, rep), arms in sorted(pairs.items()):
        if set(arms) != {"orig", "trim"}:
            print(f"{name} rep {rep}: incomplete pair {sorted(arms)}")
            continue
        a, b = load(arms["orig"]), load(arms["trim"])
        live = json.load(open(CAPTURES / LIVE[name] / "samples.json"))
        for i, (x, y) in enumerate(zip(a, b)):
            d = differences(x, y)
            vs_live = []
            if i < len(live):
                L = live[i]
                if [j["id"] for j in x["unfilteredJourneys"]] != [j["id"] for j in L["unfilteredJourneys"]]:
                    vs_live.append("unfilteredJourneys")
                for k in ("networkRequests", "responseBytes", "boardsCovered", "incompleteBoards"):
                    if x["counters"].get(k) != L["counters"].get(k):
                        vs_live.append(f"{k} {L['counters'].get(k)}->{x['counters'].get(k)}")
            row = {"capture": name, "rep": rep, "sample": x["process"], "identical": not d, "differences": d,
                   "origMatchesLive": not vs_live, "origVsLive": vs_live,
                   "approximate": [(arms[k] / "approximate-queries.json").exists() for k in ("orig", "trim")],
                   "orig": {"total": x["total_ms"], "bytes": x["counters"]["responseBytes"],
                            "memory": x.get("peak_memory_bytes"), **{t: x["stages_ms"].get(t) for t in TIMING}},
                   "trim": {"total": y["total_ms"], "bytes": y["counters"]["responseBytes"],
                            "memory": y.get("peak_memory_bytes"), **{t: y["stages_ms"].get(t) for t in TIMING}}}
            report.append(row)
            o, t = row["orig"], row["trim"]
            print(f"{name:8s} r{rep} {x['process']:8s} {'IDENTICAL' if not d else 'DIFFERS ' + str(d)}"
                  f"{'' if not vs_live else '  orig-vs-live ' + str(vs_live)}"
                  f"  total {o['total']:.0f}->{t['total']:.0f}  decode {o['decode']}->{t['decode']}"
                  f"  prep {o['providerBoardPreparation']:.1f}->{t['providerBoardPreparation']:.1f}"
                  f"  MB {o['bytes']/1e6:.1f}->{t['bytes']/1e6:.1f}"
                  f"  peakMB {o['memory']/1e6:.0f}->{t['memory']/1e6:.0f}")
    if report:
        same = sum(r["identical"] for r in report)
        print(f"\n{same} of {len(report)} samples identical; orig matches live in "
              f"{sum(r['origMatchesLive'] for r in report)} of {len(report)}")
        for key in ("total", "decode", "providerBoardPreparation", "memory"):
            delta = [r["trim"][key] - r["orig"][key] for r in report if r["trim"][key] is not None]
            print(f"  {key}: median change {statistics.median(delta):.1f}, range {min(delta):.1f} .. {max(delta):.1f}")
    if "--json" in sys.argv:
        pathlib.Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
