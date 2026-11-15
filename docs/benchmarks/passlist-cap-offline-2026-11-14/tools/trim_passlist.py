"""Cap recorded ATP passlists at K stops (simulating departureBoard passlistMaxStops=K), offline.

usage: python3 -I trim_passlist.py <capture-dir> <output-dir> <K> [--fields] [--keep-last]

Every recorded passlist starts at the board stop, so the cap keeps the board stop plus the next K-1 stops.
That is an assumption about ATP's passlistMaxStops, which is unverified (no live request was made).
--keep-last keeps the first K - 1 stops and the last stop instead, which is what ATP's passlistMaxStops
returned in the 15 November live probe (probe/README.md).
--fields also applies the CAND-12 a field trim (trim.py). Metadata is copied unchanged, so the replay
still matches each request by its URL. Never writes below <capture-dir>.
"""
import gzip, json, pathlib, shutil, sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import trim  # noqa: E402  (the CAND-12 a trimmer, copied next to this file)


def cap(departure, k, counts, keep_last=False):
    stops = departure.get("Stops")
    if not isinstance(stops, dict) or "Stop" not in stops:
        return departure
    rows = trim.as_list(stops["Stop"])
    counts["passlists"] += 1
    counts["stopsBefore"] += len(rows)
    if len(rows) > k:
        counts["capped"] += 1
        rows = rows[: k - 1] + rows[-1:] if keep_last else rows[:k]
    counts["stopsAfter"] += len(rows)
    out = dict(departure)
    out["Stops"] = dict(stops, Stop=rows)
    return out


def main():
    source, target = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
    k, fields, keep_last = int(sys.argv[3]), "--fields" in sys.argv[4:], "--keep-last" in sys.argv[4:]
    assert k >= 2 if keep_last else k >= 1
    assert source != target and source not in target.parents, "output must be outside the capture"
    (target / "network").mkdir(parents=True, exist_ok=False)
    for name in ("samples.json", "bike-snapshot.json"):
        if (source / name).exists():
            shutil.copy2(source / name, target / name)
    counts, checks, totals = Counter(), Counter(), Counter()
    for meta_path in sorted((source / "network").glob("*.json")):
        if ".body." in meta_path.name:
            continue
        meta = json.loads(meta_path.read_text())
        shutil.copy2(meta_path, target / "network" / meta_path.name)
        body_name = pathlib.Path(meta["body"]).name
        raw = (source / "network" / body_name).read_bytes()
        board = json.loads(raw)
        if fields:
            board = trim.pick(board, trim.BOARD_KEEP)
        if "Departure" in board:
            rows = [cap(r, k, counts, keep_last) for r in trim.as_list(board["Departure"])]
            board["Departure"] = [trim.trim_departure(r, checks) for r in rows] if fields else rows
        data = trim.compact(board)
        (target / "network" / body_name).write_bytes(data)
        totals["bodies"] += 1
        totals["raw"] += len(raw)
        totals["trimmed"] += len(data)
        totals["rawGzip"] += len(gzip.compress(raw, 6))
        totals["trimmedGzip"] += len(gzip.compress(data, 6))
        totals["recordedEncoded"] += sum(t.get("encodedResponseBytes", 0)
                                         for t in meta.get("transport", {}).get("transactions", []))
    stats = {"k": k, "keepLast": keep_last, "fields": fields, "totals": dict(totals), "passlists": dict(counts), "checks": dict(checks)}
    (target / "trim-stats.json").write_text(json.dumps(stats, indent=2))
    t = totals
    print(f"{source.name} K={k}{' +last' if keep_last else ''}{' +fields' if fields else ''}: {t['bodies']} bodies, decoded "
          f"{t['raw']/1e6:.2f} -> {t['trimmed']/1e6:.2f} MB ({100*(1-t['trimmed']/t['raw']):.0f} % less), gzip "
          f"{t['rawGzip']/1e6:.2f} -> {t['trimmedGzip']/1e6:.2f} MB ({100*(1-t['trimmedGzip']/t['rawGzip']):.0f} % less), "
          f"{counts['capped']}/{counts['passlists']} passlists capped")


if __name__ == "__main__":
    main()
