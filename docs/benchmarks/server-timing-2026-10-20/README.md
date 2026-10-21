# Relay Server-Timing, first live round (Tuesday 20 October 2026, 20:57)

This is one live `live-now` round with the relay's new `Server-Timing` header. It splits each board's
server wait into ATP time and relay plus network time. See the step 7 status in
[ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md).

- **Code:**
  - App: Release simulator build of Verkeier `fa5833b`, from a clean export plus the walking graph files.
  - Engine: MobilitéitKit `00078b6`.
  - Relay: `verkeier-relay` `f9c9f75`, deployed as version `aef3e2b5`.
- **Machine:** MacBook Air M4 with the iPhone 17 simulator, **on battery power** (the owner's choice for this
  run), with Low Power Mode off. No other build or benchmark was running, and the 1-minute load was 3.8. The
  transfer-walk build (CPU canary) took 2,053 ms, which is normal.
- **ATP requests:** 78.
- **Command:** [`run.sh`](run.sh), which runs `Scripts/benchmark_routes.py --scenarios live-now --warm 1
  --cold 1 --maximum-limit-ms 0 --request-budget 100`. The first `=== live round` line in its log says
  `power=AC`: the script printed that label as fixed text, and the Mac was on battery. The script now prints
  the real power source.

## Header

A forwarded response looks like this:

```
upstream;dur=249.0;desc="headers", edge;desc="FRA", cfExtPri
```

- `upstream` is how long the Worker waited for ATP's response headers.
- `edge` is the Cloudflare location. All 78 requests ran in Frankfurt (FRA).
- Cloudflare appends its own `cfExtPri` entry.

The engine stores the header as `HTTPTransportMetrics.serverTiming`. The script writes a `relaySplit` per
sample.

## Split per sample

| Sample | Total, ms | Client server wait, median | ATP (`upstream`), median / max | Relay and network, median / max | Transfer, median |
|---|---:|---:|---:|---:|---:|
| Priming | 3,161 | 708 | 604 / 889 | 104 / 282 | 10 |
| Warm | 2,037 | 512 | 402 / 794 | 70 / 249 | 10 |
| Cold | 2,437 | 639 | 560 / 910 | 117 / 186 | 9 |

- **ATP accounts for about 80–85 % of each board's server wait.** The relay hop from the simulator through
  Frankfurt and back, plus the Worker, adds a median of 70–117 ms.
- **The slowest board in every sample is the CAND-28 hub board at Luxexpo** (`000200417050`, 28 lines this
  evening). Its ATP wait was 794–910 ms, plus 70–86 ms of relay time and 33–491 ms of transfer.
- **The gate passes in all three samples**, at 2.0–3.2 s. Each sample ran two passes; the cause is below,
  in [Why each sample ran two passes](#why-each-sample-ran-two-passes).
- **Coverage:** of the 5 journeys, 2 were fully live, 2 partly live and 1 schedule-only, the same in every
  sample. No board was incomplete. Late-evening trips without realtime data are a likely reason, but I haven't
  checked that.
- **Limits of this run:**
  - At 20:57 ATP was fast, so this round doesn't explain the slow 19:05 rounds of
    [step 7](../step7-2026-10-20/README.md). A run in a slow period will show whether ATP or the relay slows
    down.
  - Body transfer is streamed and isn't split. A Worker's clock only advances across I/O, so the Worker
    can't time the body.

## Why each sample ran two passes

I found this offline by replaying this round's recorded responses (`--capture-directory L1/network
--replay-latency`, request budget 0), so no ATP requests were sent. The plain replay reproduces the live
round: the same journeys, recommendation and coverage, and two passes. A diagnostic build then showed the
chain. It used the engine at `00078b6` plus temporary log lines
([`pass2/diagnostic-engine.diff`](pass2/diagnostic-engine.diff)). The chain is the same in all three samples:

1. **Pass 0 picked a journey through Héienhaff.** It takes bus 29 at 21:29 from Senningerberg to Héienhaff
   (arriving 21:31), walks to the Héienhaff P+R tram stop and takes the T1 at 21:33:50 to Kirchberg. It was
   the third of the six journeys selected for live checks.
2. **Discovery had not fetched that tram stop.** Discovery fetched 24 boards: the 8 stops nearest the
   origin and 16 others, mostly in Kirchberg. Héienhaff P+R T1 (`000200508005`) is a transfer stop and was
   not among them. The tram's event at Héienhaff therefore came only from the timetable. So the check after
   pass 0 asked for that board (`time=21:30&duration=90&lines=T1`), which took 162–390 ms.
3. **The board moved every tram 50 s earlier.** All 9 T1 departures on it were on time, but ATP gives
   whole minutes (21:33) and GTFS has seconds (21:33:50). The engine uses ATP's reported minute as the
   time, by design since `60af526`. So each tram now leaves 50 s earlier. That changes the routing inputs,
   which starts another pass.
4. **Pass 2 dropped the Héienhaff journey.** With the tram at 21:33:00, the connection from bus 29 shrinks
   from 2:50 to 2:00 minutes and no longer holds. Pass 2 built 18 journeys instead of 19, without it. The
   final picks need no further boards, so the loop stops there.

The second pass cost 685, 464 and 448 ms in the priming, warm and cold samples. That is measured from the
end of pass 0's candidate building to the end of pass 2's. In step 7's samples (18:52–19:06), the check
after pass 0 never changed routing inputs, so they ran one pass.

**Experiment: the same board in discovery.** I added that board to the first discovery batch, with the
same query, then replayed. It went above the 24-board limit, so this is a test of the cause, not a
proposed change. The control is the same build without the extra board:

| Run | Passes | Priming, ms | Warm, ms | Cold, ms | Requests |
|---|---:|---:|---:|---:|---:|
| Control | 2 | 2,331 | 2,123 | 2,333 | 26 |
| Héienhaff T1 in discovery | 1 | 1,837 | 1,662 | 1,811 | 26 |

- **Results are identical to the control:** options, recommendation, coverage and journeys. Only the
  walking counters fell, because there was one scan fewer.
- **Both runs show one more option than the live app result.** The app hides dominated options using
  wall-clock time. These replays ran at 21:18, after the first option's 21:17 bus, so that option no
  longer hid the 322 → 211 → 18 journey. The engine's own journeys (`unfilteredJourneys`) match the live
  round in both runs, and the diagnostic replay at 21:13 matched the live round fully.
- **This is one replay pair.** Replay timings vary by 10–20 %.

**What this means:**
- **This second pass is not wasted.** Pass 0 picked a connection that ATP's times rule out. The pass goes
  away only if discovery fetches the transfer stop up front. CAND-29 (transfer-first ordering) aims at
  exactly that. Héienhaff P+R is one ride from the destination, so CAND-29 would likely rank it ahead of
  the zero-ride Kirchberg stops. CAND-29 changes live behaviour and needs owner approval.
- **Nearly every newly fetched board counts as a routing change.** ATP reports whole minutes, and most
  GTFS times here have seconds (21:17:50, 21:30:07, 21:33:50). In the first discovery batch, all 130
  patched trips changed routing inputs. So the check that skips pass 2 when only freshness changes rarely
  applies. Changing the minute rule would change results, so I'm not proposing it.

## Files

| File | Content |
|---|---|
| `L1/samples.json` | Every sample, with `relaySplit` and each request's `metrics.serverTiming` |
| `L1/summary.json`, `L1/transport.json`, `L1/optimisation.json` | Medians, response metadata (no bodies), and the CPU canary |
| `pass2/control/`, `pass2/heienhaff-in-discovery/` | Samples and summary of the two experiment replays |
| `pass2/debug-log-cold.txt` | The diagnostic build's log for the cold sample |
| `pass2/diagnostic-engine.diff` | The temporary log lines and the extra discovery board (enabled by `PASS2_INJECT=1`), against `00078b6`. They were applied to a scratch copy only and committed nowhere |

The raw bodies and the app build are in `~/Developer/Verkeier-captures/server-timing-2026-10-20/`, outside git.
