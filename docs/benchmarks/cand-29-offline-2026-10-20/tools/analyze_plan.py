"""Plan-level comparison of the diagnostic (PASS_DEBUG) replays. usage: analyze_plan.py <runs/plan dir> [--json out.json]

For each capture and arm: boards discovery plans, how many of the arm's first-batch queries exist in the recording, and
whether the stops the control had to fetch after discovery (the late boards) are in the arm's discovery."""
import json, re, sys, pathlib, glob

plan_dir = pathlib.Path(sys.argv[1])
out_json = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--json" else None


def parse(log_path):
    lines = open(log_path, errors="replace").read().splitlines()
    # Only the first sample of the process (priming): stop at the second "cand29 reachability built" line.
    started = 0
    first = []
    for line in lines:
        if "cand29 reachability built" in line:
            started += 1
            if started > 1 and any("pass wave" in x or "discovery wave" in x for x in first):
                break
        first.append(line)
    waves = {}
    access = None
    hits = misses = 0
    missing_stops = set()
    hit_queries = []
    heien = []
    completions = []
    post = []
    spec = []
    passes = 0
    missing_queries = []
    cand_counts = []
    for line in first:
        m = re.match(r"ROUTING_DEBUG discovery wave (\d+) boards (.*)", line)
        if m:
            waves[int(m.group(1))] = re.findall(r"(\d{12})\(([^)]*(?:\([^)]*\))?[^)]*)\)=(\d+)(P?)", m.group(2))
        if line.startswith("ROUTING_BENCHMARK_REPLAY_QUERY"):
            hits += 1
            hit_queries.append(line)
        if line.startswith("ROUTING_BENCHMARK_ABORT"):
            misses += 1
            missing_queries.append(line.split("missing-replay-query ", 1)[1])
            m2 = re.search(r"id=(\d+)", line)
            if m2:
                missing_stops.add(m2.group(1))
        m = re.search(r"Heienhaff P\+R T1 000200508005 tight=(\S+) optimistic=(\S+) position=(\S+)", line)
        if m:
            heien.append(m.groups())
        if "frontier candidates=" in line:
            cand_counts.append(line.split("ROUTING_DEBUG ")[1])
        m = re.match(r"ROUTING_DEBUG completion result changed=(\w+) stops=\[(.*?)\] patches=(\d+)", line)
        if m:
            stops = re.findall(r'"(\d+)"', m.group(2))
            completions.append((m.group(1), stops, int(m.group(3))))
            (post if passes > 0 else spec).append(stops)
        if line.startswith("ROUTING_DEBUG pass wave="):
            passes += 1
    return dict(waves=waves, hits=hits, misses=misses, missing_stops=sorted(missing_stops), heien=heien,
                completions=completions, passes=passes, cand_counts=cand_counts, post=post, spec=spec,
                missing_queries=missing_queries)


def stops_of(waves):
    out = []
    for w in sorted(waves):
        out += [s[0] for s in waves[w]]
    return out


rows = []
for cap in sorted({p.name.rsplit("-", 1)[0] for p in plan_dir.iterdir() if p.is_dir()}):
    ctl_logs = glob.glob(str(plan_dir / f"{cap}-control" / "*-warm.log"))
    ctl = parse(ctl_logs[0])
    ctl_disc = set(stops_of(ctl["waves"]))
    # Boards asked after discovery: by the speculative completion (before pass 0) and after pass 0.
    post_stops = []
    for stops in ctl["post"]:
        for s in stops:
            if s not in post_stops:
                post_stops.append(s)
    post_new = [s for s in post_stops if s not in ctl_disc]
    spec_stops = [s for stops in ctl["spec"] if len(stops) <= 12 for s in stops]
    spec_new = [s for s in dict.fromkeys(spec_stops) if s not in ctl_disc]
    late = post_new
    print(f"=== {cap}: control passes {ctl['passes']}, discovery {len(ctl_disc)} stops; speculative-completion boards outside discovery: {spec_new}; boards asked after pass 0: {post_stops} (outside discovery: {post_new})")
    row = {"capture": cap, "control": {"passes": ctl["passes"], "discovery": sorted(ctl_disc), "post_pass0": post_stops, "post_pass0_outside_discovery": late, "speculative_outside_discovery": spec_new}}
    for arm in ("c29", "c29arr"):
        logs = glob.glob(str(plan_dir / f"{cap}-{arm}" / "*-warm.log"))
        a = parse(logs[0])
        d = set(stops_of(a["waves"]))
        covered_late = [s for s in late if s in d]
        total = a["hits"] + a["misses"]
        spec_cov = [s for s in spec_new if s in d]
        print(f"  {arm:7s}: discovery {len(d)} stops; shared with control {len(d & ctl_disc)}; recorded queries {a['hits']} of {total}; missing queries {a['misses']} at {len(a['missing_stops'])} stops; "
              f"post-pass-0 boards outside control discovery now in discovery: {len(covered_late)}/{len(late)} {covered_late}; speculative: {len(spec_cov)}/{len(spec_new)}; Heienhaff position {a['heien']}")
        mq = plan_dir.parent / "missing-queries"
        mq.mkdir(exist_ok=True)
        (mq / f"{cap}-{arm}.txt").write_text("\n".join(a["missing_queries"]) + "\n")
        row[arm] = {"spec_covered": spec_cov, "discovery": sorted(d), "shared_with_control": len(d & ctl_disc), "queries_recorded": a["hits"],
                    "queries_missing": a["misses"], "late_covered": covered_late, "heienhaff": a["heien"],
                    "waves": {str(k): [x[0] for x in v] for k, v in a["waves"].items()}, "ranks": {str(k): [x[2] for x in v] for k, v in a["waves"].items()}}
    row["control"]["waves"] = {str(k): [x[0] for x in v] for k, v in ctl["waves"].items()}
    row["control"]["ranks"] = {str(k): [x[2] for x in v] for k, v in ctl["waves"].items()}
    row["control"]["cand_counts"] = ctl["cand_counts"]
    rows.append(row)

if out_json:
    json.dump(rows, open(out_json, "w"), indent=1)
