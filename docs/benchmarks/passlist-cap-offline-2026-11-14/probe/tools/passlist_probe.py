"""Two-request probe of ATP departureBoard passlistMaxStops, sent by the app in the iOS Simulator.

usage:
  python3 -I passlist_probe.py run --app <Verkeier.app> --device <udid> --stop <ATP id> --cap <K> --out <dir>
                                   [--duration 30] [--date YYYY-MM-DD --time HH:MM:SS]
                                   (--base-url http://127.0.0.1:<port> [--mock-log requests.jsonl] | --live)
  python3 -I passlist_probe.py analyze <dir> [--cap K]

`run` launches the app's `passlist-probe` scenario (PasslistProbe.swift), which sends exactly two
boards for one stop and window, the first without and the second with passlistMaxStops, saves both
bodies, and then copies them to <dir> and analyses them.

Without --live the run is a dry run. It refuses unless the app was built with an empty
API_PROXY_URL and --base-url answers the mock relay's marker path, so nothing can reach the relay
or ATP. --live sends the two requests through the app's relay (or through --base-url, for a local
`wrangler dev` relay, which is live too). Never run it on a physical device.

`analyze` matches departures by JourneyDetailRef, date and time and classifies each capped passlist
against its full one: unchanged, prefix, prefix+last (terminus kept), subsequence or other.
"""
import json, os, pathlib, plistlib, shutil, subprocess, sys, time, urllib.request
from collections import Counter

BUNDLE = "dev.pedrocordeiro.Verkeier"
MOCK_MARKER = "/__passlist_probe_mock"


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def as_list(value):
    return value if isinstance(value, list) else [value]


# --- analysis -------------------------------------------------------------------------------------

def departures(board):
    out = {}
    for row in as_list(board.get("Departure", [])):
        ref = (row.get("JourneyDetailRef") or {}).get("ref")
        key = (ref, row.get("date"), row.get("time"), row.get("stopExtId"))
        out[key] = row
    return out


def stops_of(row):
    stops = row.get("Stops")
    if not isinstance(stops, dict) or "Stop" not in stops:
        return None
    return as_list(stops["Stop"])


def identity(stop):
    return (stop.get("extId") or stop.get("id"), stop.get("routeIdx"))


def is_subsequence(small, large):
    it = iter(large)
    return all(any(x == y for y in it) for x in small)


def classify(full, capped):
    f, c = [identity(s) for s in full], [identity(s) for s in capped]
    if c == f:
        return "unchanged"
    if c == f[: len(c)]:
        return "prefix"
    if len(c) >= 1 and c[-1] == f[-1] and c[:-1] == f[: len(c) - 1]:
        return "prefix+last"
    if is_subsequence(c, f):
        return "subsequence" + ("+first" if c and c[0] == f[0] else "") + ("+last" if c and c[-1] == f[-1] else "")
    return "other"


def analyze(folder, cap=None):
    folder = pathlib.Path(folder)
    raw_full, raw_capped = (folder / "full.json").read_bytes(), (folder / "capped.json").read_bytes()
    meta = {}
    for label in ("full", "capped"):
        path = folder / f"{label}.meta.json"
        meta[label] = json.loads(path.read_text()) if path.exists() else {}
    cap = cap if cap is not None else meta["capped"].get("cap")
    full, capped = json.loads(raw_full), json.loads(raw_capped)
    F, C = departures(full), departures(capped)
    shared = sorted(set(F) & set(C), key=str)
    shapes, lengths, over, starts, field_keys, rt_keys, departure_keys = (Counter() for _ in range(7))
    examples = {}
    stops_full = stops_capped = with_passlist = longer_than_cap = 0
    for key in shared:
        x, y = F[key], C[key]
        for k in sorted((set(x) | set(y)) - {"Stops"}):
            if x.get(k) != y.get(k):
                departure_keys[k] += 1
        a, b = stops_of(x), stops_of(y)
        if a is None or b is None:
            shapes["no-passlist" if a is None and b is None else "passlist-only-one-side"] += 1
            continue
        with_passlist += 1
        stops_full += len(a)
        stops_capped += len(b)
        shape = classify(a, b)
        if shape == "unchanged":
            shape += "-short" if cap is None or len(a) <= cap else "-long(cap ignored)"
        shapes[shape] += 1
        examples.setdefault(shape, {"departure": list(key), "full": [identity(s) for s in a],
                                    "capped": [identity(s) for s in b]})
        if cap is not None and len(a) > cap:
            longer_than_cap += 1
            lengths[len(b)] += 1
            over[len(b) - cap] += 1
        board_ids = {x.get("stopExtId"), x.get("mainMastExtId")} - {None}
        starts["capped starts at the board stop" if b and (b[0].get("extId") in board_ids
               or (b[0].get("mainMast") or {}).get("extId") in board_ids) else "capped starts elsewhere"] += 1
        A = {identity(s): s for s in a}
        for s in b:
            t = A.get(identity(s))
            if t is None:
                continue
            for k in sorted(set(s) | set(t)):
                if s.get(k) != t.get(k):
                    field_keys[k] += 1
                    if k.startswith("rt") or "Prognosis" in k or k in ("cancelled", "partCancelled"):
                        rt_keys[k] += 1
    total = lambda body: sum(len(json.dumps(stops_of(r), separators=(",", ":")).encode())
                             for r in as_list(body.get("Departure", [])) if stops_of(r) is not None)
    summary = {
        "cap": cap,
        "status": [meta["full"].get("status"), meta["capped"].get("status")],
        "requestTimes": [meta["full"].get("time"), meta["capped"].get("time")],
        "bytes": {"full": len(raw_full), "capped": len(raw_capped),
                  "change": round(len(raw_capped) / len(raw_full) - 1, 3) if raw_full else None,
                  "passlistFull": total(full), "passlistCapped": total(capped)},
        "departures": {"full": len(F), "capped": len(C), "matched": len(shared),
                       "onlyFull": len(set(F) - set(C)), "onlyCapped": len(set(C) - set(F))},
        "passlists": {"matched": with_passlist, "stopsFull": stops_full, "stopsCapped": stops_capped,
                      "fullLongerThanCap": longer_than_cap},
        "shapes": dict(shapes),
        "cappedLengthWhenFullLongerThanCap": dict(sorted(lengths.items())),
        "cappedLengthMinusCap": dict(sorted(over.items())),
        "start": dict(starts),
        "stopFieldMismatches": dict(field_keys.most_common()),
        "realtimeFieldMismatches": dict(rt_keys.most_common()),
        "departureFieldMismatches": dict(departure_keys.most_common()),
        "technicalMessages": [capped.get("TechnicalMessages"), full.get("TechnicalMessages")] if
                             capped.get("TechnicalMessages") != full.get("TechnicalMessages") else None,
        "examples": examples,
    }
    summary["verdict"] = verdict(summary)
    return summary


def verdict(s):
    shapes = {k: v for k, v in s["shapes"].items() if k not in ("unchanged-short", "no-passlist")}
    n = s["passlists"]["fullLongerThanCap"]
    if s["status"] != [200, 200]:
        return f"inconclusive: status {s['status']}"
    if not n:
        return "inconclusive: no passlist was longer than the cap; pick a stop or cap with longer passlists"
    if set(shapes) == {"unchanged-long(cap ignored)"}:
        return "ATP ignored passlistMaxStops (the relay may not forward it)"
    if len(shapes) == 1:
        (shape, count), = shapes.items()
        return (f"{shape} in all {count} passlists longer than the cap; capped length minus cap "
                f"{s['cappedLengthMinusCap']}")
    return f"mixed shapes {shapes}; read the examples"


# --- run ------------------------------------------------------------------------------------------

def app_relay(app):
    with open(pathlib.Path(app) / "Info.plist", "rb") as stream:
        return plistlib.load(stream).get("API_PROXY_URL", "")


def booted(device):
    inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
    for runtime in inventory["devices"].values():
        for entry in runtime:
            if entry["udid"] == device:
                return entry["state"] == "Booted"
    raise SystemExit(f"no simulator {device} (physical devices are not supported)")


def run():
    app, device, stop, cap, out = (arg(n) for n in ("--app", "--device", "--stop", "--cap", "--out"))
    if not all((app, device, stop, cap, out)):
        raise SystemExit(__doc__)
    live, base, mock_log = "--live" in sys.argv, arg("--base-url"), arg("--mock-log")
    relay = app_relay(app)
    if live:
        print(f"LIVE: two departureBoard requests for {stop} via {base or relay or '(no relay!)'}", flush=True)
        if not (base or relay):
            raise SystemExit("the app has no relay; build it with API_PROXY_URL or pass --base-url")
    else:
        if relay:
            raise SystemExit(f"dry run refused: the app was built with API_PROXY_URL={relay!r}")
        if not base:
            raise SystemExit("dry run needs --base-url (the mock relay); pass --live for a live run")
        try:
            marker = urllib.request.urlopen(base.rstrip("/") + MOCK_MARKER, timeout=3).read()
        except OSError as error:
            raise SystemExit(f"dry run refused: {base} is not the mock relay ({error})")
        if marker != b"mock":
            raise SystemExit(f"dry run refused: {base} is not the mock relay")
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=False)
    if not booted(device):
        subprocess.run(["xcrun", "simctl", "boot", device], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "install", device, app], check=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_")}
    env |= {"SIMCTL_CHILD_ROUTING_BENCHMARK_SCENARIO": "passlist-probe",
            "SIMCTL_CHILD_ROUTING_PASSLIST_PROBE_STOP": stop,
            "SIMCTL_CHILD_ROUTING_PASSLIST_PROBE_CAP": str(int(cap)),
            "SIMCTL_CHILD_ROUTING_PASSLIST_PROBE_DURATION": str(int(arg("--duration", "30")))}
    for flag, name in (("--date", "DATE"), ("--time", "TIME"), ("--base-url", "BASE_URL")):
        if arg(flag):
            env[f"SIMCTL_CHILD_ROUTING_PASSLIST_PROBE_{name}"] = arg(flag)
    console = out / "console.log"
    folder, outcome, deadline = None, None, time.monotonic() + 120
    with console.open("w") as stream:
        process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                                    device, BUNDLE, "--routing-benchmark"], env=env, stdout=stream,
                                   stderr=subprocess.STDOUT)
        try:
            while time.monotonic() < deadline and outcome is None:
                time.sleep(0.5)
                for line in console.read_text(errors="replace").splitlines():
                    if line.startswith("ROUTING_PASSLIST_PROBE_FOLDER "):
                        folder = pathlib.Path(line.split(" ", 1)[1].strip())
                    if "ROUTING_BENCHMARK_ABORT" in line:
                        outcome = line.strip()  # the scenario still prints DONE after an abort
                        break
                    if "ROUTING_BENCHMARK_DONE" in line:
                        outcome = "done"
                if process.poll() is not None and outcome is None:
                    outcome = f"app exited {process.returncode}"
        finally:
            subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            process.wait(timeout=10)
    print(f"outcome: {outcome}", flush=True)
    if outcome != "done" or folder is None:
        raise SystemExit(f"probe failed; see {console}")
    for name in ("full.json", "capped.json", "full.meta.json", "capped.meta.json"):
        shutil.copy2(folder / name, out / name)
    if mock_log:
        verify_mock_log(pathlib.Path(mock_log), int(cap), out)
    summary = analyze(out, int(cap))
    (out / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print_summary(summary)


def verify_mock_log(log, cap, out):
    """Dry run only: the mock saw exactly two boards, identical but for passlistMaxStops on the second."""
    rows = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    boards = [dict(r["query"]) for r in rows if r["path"] == "/atp/departureBoard"]
    first, second = (boards + [{}, {}])[:2]
    checks = {
        "two board requests": len(boards) == 2,
        "first has no passlistMaxStops": "passlistMaxStops" not in first,
        "second has passlistMaxStops=cap": second.get("passlistMaxStops") == str(cap),
        "otherwise identical": {k: v for k, v in second.items() if k != "passlistMaxStops"} == first,
        "passlist=1 on both": first.get("passlist") == "1" and second.get("passlist") == "1",
    }
    (out / "mock-check.json").write_text(json.dumps({"checks": checks, "boards": boards}, indent=2))
    for name, ok in checks.items():
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not all(checks.values()):
        raise SystemExit("mock log check failed")


def print_summary(s):
    print(json.dumps({k: v for k, v in s.items() if k != "examples"}, indent=2, ensure_ascii=False))
    print("verdict:", s["verdict"])


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        run()
    elif len(sys.argv) > 2 and sys.argv[1] == "analyze":
        cap = arg("--cap")
        summary = analyze(sys.argv[2], int(cap) if cap else None)
        print_summary(summary)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
