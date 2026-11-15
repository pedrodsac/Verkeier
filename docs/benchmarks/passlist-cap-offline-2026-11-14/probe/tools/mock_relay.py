"""Local stand-in for the relay's /atp/departureBoard, for a dry run of the passlist probe.

usage: python3 -I mock_relay.py <recorded-board.json> <port> <requests.jsonl> [--shape prefix|prefix-last|thin|ignore]

Answers every /atp/departureBoard request with the recorded body. When the request carries
passlistMaxStops=K, each passlist longer than K is cut to the named shape:
  prefix       the board stop and the next K-1 stops (the offline replay's assumption)
  prefix-last  the first K-1 stops and the terminus (what ATP's WADL wording suggests)
  thin         the board stop, evenly spaced stops and the terminus
  ignore       unchanged (ATP ignoring the parameter)
Each request's path and query are appended to <requests.jsonl>. GET /__passlist_probe_mock answers
"mock", which the probe runner checks before a dry run. Binds 127.0.0.1 only and never makes a
request of its own.
"""
import json, pathlib, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qsl, urlsplit


def as_list(value):
    return value if isinstance(value, list) else [value]


def cut(rows, k, shape):
    if shape == "ignore" or len(rows) <= k:
        return rows
    if shape == "prefix":
        return rows[:k]
    if shape == "prefix-last":
        return rows[: max(k - 1, 0)] + rows[-1:] if k >= 1 else []
    if shape == "thin":
        if k < 2:
            return rows[:k]
        step = (len(rows) - 1) / (k - 1)
        return [rows[round(i * step)] for i in range(k)]
    raise SystemExit(f"unknown shape {shape}")


def capped_body(board, k, shape):
    out = dict(board)
    rows = []
    for departure in as_list(board.get("Departure", [])):
        stops = departure.get("Stops")
        if isinstance(stops, dict) and "Stop" in stops:
            departure = dict(departure, Stops=dict(stops, Stop=cut(as_list(stops["Stop"]), k, shape)))
        rows.append(departure)
    out["Departure"] = rows
    return out


def main():
    recorded, port, log = pathlib.Path(sys.argv[1]), int(sys.argv[2]), pathlib.Path(sys.argv[3])
    shape = sys.argv[sys.argv.index("--shape") + 1] if "--shape" in sys.argv else "prefix-last"
    board = json.loads(recorded.read_bytes())

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parts = urlsplit(self.path)
            query = parse_qsl(parts.query, keep_blank_values=True)
            with log.open("a") as stream:
                stream.write(json.dumps({"path": parts.path, "query": query}) + "\n")
            if parts.path == "/__passlist_probe_mock":
                # The probe runner's dry-run guard: only this mock answers it.
                self.send_response(200)
                self.send_header("Content-Length", "4")
                self.end_headers()
                self.wfile.write(b"mock")
                return
            if parts.path != "/atp/departureBoard":
                self.send_response(404)
                self.end_headers()
                return
            cap = dict(query).get("passlistMaxStops")
            body = board if cap is None else capped_body(board, int(cap), shape)
            data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    print(f"mock relay on 127.0.0.1:{port} shape={shape}", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
