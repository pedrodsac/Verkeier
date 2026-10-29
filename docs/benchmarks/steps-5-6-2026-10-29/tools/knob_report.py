"""Step 6 knob replays: per capture and sample kind, median of each variant against the base build.

usage: python3 -I knob_report.py <runs-dir> [--json out.json]. Run folders are <capture>-C[-knob]-<rep>.
"""
import json, pathlib, re, statistics as st, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from compare_arms import differences
STAGES = ["realtime", "walkingPreparation", "firstRender", "refinement", "decode", "raptor", "candidateBuilding"]
runs = pathlib.Path(sys.argv[1]); data = {}
for d in sorted(runs.iterdir()):
    m = re.fullmatch(r"(.+)-(C(?:-[a-z0-9]+)?)-(\d+)", d.name)
    if not m or not (d / "samples.json").exists(): continue
    canary = json.load(open(d / "optimisation.json")).get("build_ms") if (d / "optimisation.json").exists() else None
    for i, s in enumerate(json.load(open(d / "samples.json"))):
        data.setdefault((m[1], i), {}).setdefault(m[2], []).append(dict(sample=s, rep=int(m[3]), canary=canary))
report = []; deltas = {}
for (cap, i), variants in sorted(data.items()):
    base = variants.get("C", [])
    if not base: continue
    line = f"{cap:8s} s{i} base total {st.median(r['sample']['total_ms'] for r in base):5.0f}"
    for v, rows in sorted(variants.items()):
        if v == "C": continue
        same = all(not differences(b["sample"], r["sample"]) for b in base for r in rows if b["rep"] == r["rep"])
        dt = st.median(r["sample"]["total_ms"] for r in rows) - st.median(r["sample"]["total_ms"] for r in base)
        stages = {k: st.median(r["sample"]["stages_ms"].get(k, 0) for r in rows) - st.median(b["sample"]["stages_ms"].get(k, 0) for b in base) for k in STAGES}
        deltas.setdefault(v, []).append(dict(total=dt, **stages))
        line += f" | {v}: {'=' if same else '≠'} total {dt:+5.0f} rt {stages['realtime']:+4.0f} warm {stages['walkingPreparation']:+4.0f} render {stages['firstRender']:+4.0f}"
        report.append(dict(capture=cap, sample=i, variant=v, identical=same, total=dt, **stages))
    print(line)
for v, rows in deltas.items():
    print(f"{v}: median change total {st.median(r['total'] for r in rows):+.0f} ms, realtime {st.median(r['realtime'] for r in rows):+.0f}, "
          f"warm-up {st.median(r['walkingPreparation'] for r in rows):+.0f}, render {st.median(r['firstRender'] for r in rows):+.0f} (n={len(rows)})")
if "--json" in sys.argv: pathlib.Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(report, indent=2))
