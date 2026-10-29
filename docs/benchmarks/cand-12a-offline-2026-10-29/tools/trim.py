"""Trim recorded ATP departure boards to the fields routing reads (CAND-12 a), offline.

usage: python3 -I trim.py <capture-dir> <output-dir>

Reads <capture-dir>/network/*.json (metadata, copied unchanged) and *.body.json (bodies), writes trimmed
bodies to <output-dir>/network/, copies samples.json and bike-snapshot.json, and writes
<output-dir>/trim-stats.json. Never writes below <capture-dir>.

The keep-list mirrors MobilitéitKit 1bd2ebf: the Decodable models in MobiliteitAPIClient.swift, minus fields no
routing consumer reads (DepartureBoardCache, DepartureBoardSnapshot, CachedBoardResponse and
HafasRealtimeRoutingProvider*). The engine takes the first `Product` only.
"""
import gzip, json, pathlib, shutil, subprocess, sys
from collections import Counter

BOARD_KEEP = ("Departure", "errorCode", "errorText")
DEPARTURE_KEEP = ("JourneyDetailRef", "Product", "Stops", "stopExtId", "time", "date", "rtTime", "rtDate",
                  "prognosisType", "cancelled", "reachable", "direction", "platform", "rtPlatform")
PRODUCT_KEEP = ("name", "line", "lineId", "catOutS")
STOP_KEEP = ("name", "extId", "routeIdx", "depTime", "depDate", "arrTime", "arrDate", "rtDepTime", "rtDepDate",
             "rtArrTime", "rtArrDate", "depTrack", "arrTrack", "rtDepTrack", "rtArrTrack", "depPrognosisType",
             "arrPrognosisType", "cancelledDeparture", "cancelledArrival", "cancelled", "boarding", "alighting",
             "rtBoarding", "rtAlighting")


def pick(value, keys):
    return {k: value[k] for k in keys if k in value}


def as_list(value):
    return value if isinstance(value, list) else [value]


def trim_departure(row, checks):
    out = pick(row, DEPARTURE_KEEP)
    if isinstance(out.get("JourneyDetailRef"), dict):
        out["JourneyDetailRef"] = pick(out["JourneyDetailRef"], ("ref",))
    if "Product" in out:
        products = as_list(out["Product"])
        checks["products>1"] += len(products) > 1
        at_stop = (row.get("ProductAtStop") or {}).get("line")
        if at_stop is not None and products and products[0].get("line") != at_stop:
            checks["ProductAtStop.line != Product[0].line"] += 1
        out["Product"] = [pick(products[0], PRODUCT_KEEP)] if products else []
    for key in ("platform", "rtPlatform"):
        if isinstance(out.get(key), dict):
            out[key] = pick(out[key], ("text",))
    stops = out.get("Stops")
    if isinstance(stops, dict) and "Stop" in stops:
        trimmed = []
        for stop in as_list(stops["Stop"]):
            sid = stop.get("id")
            if sid is not None and ("@" not in sid or "extId" not in stop):
                checks["passlist id usable without extId"] += 1
            trimmed.append(pick(stop, STOP_KEEP))
        out["Stops"] = {"Stop": trimmed}
    elif stops is not None:
        checks["Stops without Stop key"] += 1
    return out


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()


def brotli(data):
    return len(subprocess.run(["brotli", "-c", "-q", "4"], input=data, capture_output=True, check=True).stdout)


def main():
    source, target = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
    assert source != target and source not in target.parents, "output must be outside the capture"
    (target / "network").mkdir(parents=True, exist_ok=False)
    for name in ("samples.json", "bike-snapshot.json"):
        if (source / name).exists():
            shutil.copy2(source / name, target / name)
    checks, dropped = Counter(), Counter()
    totals = Counter()
    per_body = []
    for meta_path in sorted((source / "network").glob("*.json")):
        if ".body." in meta_path.name:
            continue
        meta = json.loads(meta_path.read_text())
        shutil.copy2(meta_path, target / "network" / meta_path.name)
        body_name = pathlib.Path(meta["body"]).name
        raw = (source / "network" / body_name).read_bytes()
        board = json.loads(raw)
        for key in board:
            if key not in BOARD_KEEP:
                dropped["board." + key] += len(compact(board[key]))
        trimmed_board = pick(board, BOARD_KEEP)
        if "Departure" in trimmed_board:
            trimmed_board["Departure"] = [trim_departure(r, checks) for r in as_list(trimmed_board["Departure"])]
        data = compact(trimmed_board)
        (target / "network" / body_name).write_bytes(data)
        encoded = sum(t.get("encodedResponseBytes", 0) for t in meta.get("transport", {}).get("transactions", []))
        row = {"body": body_name, "url": meta["url"], "raw": len(raw), "trimmed": len(data),
               "rawGzip": len(gzip.compress(raw, 6)), "trimmedGzip": len(gzip.compress(data, 6)),
               "rawBrotli": brotli(raw), "trimmedBrotli": brotli(data), "recordedEncoded": encoded}
        per_body.append(row)
        for k, v in row.items():
            if isinstance(v, int):
                totals[k] += v
        totals["bodies"] += 1
    stats = {"totals": dict(totals), "checks": dict(checks), "droppedBoardKeys": dict(dropped), "bodies": per_body}
    (target / "trim-stats.json").write_text(json.dumps(stats, indent=2, ensure_ascii=False))
    t = totals
    print(f"{source}: {t['bodies']} bodies, decoded {t['raw']/1e6:.2f} -> {t['trimmed']/1e6:.2f} MB "
          f"({100*(1-t['trimmed']/t['raw']):.0f} % less), gzip {t['rawGzip']/1e6:.2f} -> {t['trimmedGzip']/1e6:.2f} MB, "
          f"brotli {t['rawBrotli']/1e6:.2f} -> {t['trimmedBrotli']/1e6:.2f} MB, recorded encoded {t['recordedEncoded']/1e6:.2f} MB; "
          f"checks {dict(checks)}")


if __name__ == "__main__":
    main()
