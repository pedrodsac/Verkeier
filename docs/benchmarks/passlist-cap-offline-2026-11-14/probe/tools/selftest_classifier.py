"""Offline self-test of passlist_probe.analyze: every mock shape, an offline trim, and a realtime change.

usage: python3 -I selftest_classifier.py <recorded-board.json> <work-dir> [<trimmed-board.json>]

<trimmed-board.json> is the same board after trim_passlist.py at K = 10 (optional). Writes one folder
per case below <work-dir>, which must not exist yet.
"""
import copy, importlib.util, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    mock, probe = load("mock_relay"), load("passlist_probe")
    board = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
    work = pathlib.Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=False)

    def case(name, capped, cap=10):
        folder = work / name
        folder.mkdir()
        (folder / "full.json").write_bytes(json.dumps(board).encode())
        (folder / "capped.json").write_bytes(json.dumps(capped).encode())
        for label in ("full", "capped"):
            (folder / f"{label}.meta.json").write_text(json.dumps({"status": 200, "cap": cap}))
        s = probe.analyze(folder)
        print(f"{name:12s} shapes={s['shapes']} length-K={s['cappedLengthMinusCap']} "
              f"realtime={s['realtimeFieldMismatches']} departures={s['departures']} bytes={s['bytes']['change']}")
        print(f"{'':12s} verdict: {s['verdict']}")

    for shape in ("prefix", "prefix-last", "thin", "ignore"):
        case(shape, mock.capped_body(board, 10, shape))
    if len(sys.argv) > 3:
        case("trimmed-k10", json.loads(pathlib.Path(sys.argv[3]).read_bytes()))
    changed = copy.deepcopy(mock.capped_body(board, 10, "prefix-last"))
    changed["Departure"][0]["Stops"]["Stop"][1]["rtDepTime"] = "23:59:00"
    changed["Departure"].pop()
    case("rt-changed", changed)


if __name__ == "__main__":
    main()
