"""Find which capped passlists move the c28-rev end-stop tie (612 original, 127 terminus-kept).

usage: python3 -I bisect_tie.py <passlist-dir>

Builds variants of captures-k10last/c28-rev with a subset of passlists restored to the original, replays
each on the unchanged old engine (V=1, no flags, offline, --request-budget 0) and checks the end stop.
Bisects while exactly one half flips the tie; stops and reports when neither half does on its own.
"""
import json, os, pathlib, shutil, subprocess, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import trim  # noqa: E402

B = pathlib.Path(sys.argv[1])
ORIG, CAPPED = B / "captures-orig/c28-rev", B / "captures-k10last/c28-rev"
WORK, RUNS = B / "bisect", B / "runs5"
ID = "1962>{}:24360544@20261019:21-26|24365864@20261019:28-30"
K = 10


def L(v):
    return v if isinstance(v, list) else [v]


def capped_items():
    items = []
    for p in sorted((ORIG / "network").glob("*.body.json")):
        board = json.loads(p.read_bytes())
        for i, d in enumerate(L(board.get("Departure", []))):
            if len(L(d.get("Stops", {}).get("Stop", []))) > K:
                items.append((p.name, i))
    return items


def build(name, restore):
    target = WORK / name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(CAPPED, target)
    by_body = {}
    for body, i in restore:
        by_body.setdefault(body, []).append(i)
    for body, indices in by_body.items():
        full = L(json.loads((ORIG / "network" / body).read_bytes())["Departure"])
        capped = json.loads((target / "network" / body).read_bytes())
        rows = L(capped["Departure"])
        for i in indices:
            rows[i] = full[i]
        capped["Departure"] = rows
        (target / "network" / body).write_bytes(trim.compact(capped))
    return target


def end_stop(name, restore):
    capture = build(name, restore)
    out = RUNS / f"c28-rev-bisect-{name}"
    env = dict(os.environ, V="1", APPROX="1")
    rc = subprocess.run([str(B / "tools/replay_c.sh"), str(capture), "live-reverse", "one", str(out)], env=env).returncode
    text = (out / "samples.json").read_text() if (out / "samples.json").exists() else ""
    stops = [s for s in ("612", "127") if ID.format(s) in text]
    print(f"  {name}: {len(restore)} restored, rc {rc}, end stop {stops}", flush=True)
    shutil.rmtree(capture)
    return stops


def main():
    WORK.mkdir(exist_ok=True)
    items = capped_items()
    print(f"{len(items)} capped passlists", flush=True)
    step = 0
    assert end_stop(f"s{step}-all", items) == ["612"], "restoring every passlist should give the original end stop"
    pool = items
    while len(pool) > 1:
        step += 1
        half = len(pool) // 2
        a, b = pool[:half], pool[half:]
        if end_stop(f"s{step}a", a) == ["612"]:
            pool = a
        elif end_stop(f"s{step}b", b) == ["612"]:
            pool = b
        else:
            print(f"neither half alone flips the tie; pool of {len(pool)} left", flush=True)
            break
    print("RESULT", json.dumps(pool[:40]), flush=True)
    for body, i in pool[:5]:
        d = L(json.loads((ORIG / "network" / body).read_bytes())["Departure"])[i]
        rows = L(d["Stops"]["Stop"])
        print(body, i, d.get("name", "").strip(), d.get("stop"), d.get("time"), "->", d.get("direction"),
              f"{len(rows)} stops", flush=True)
    print("BISECTDONE", flush=True)


if __name__ == "__main__":
    main()
