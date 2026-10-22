# Relay Server-Timing, evening rounds (Thursday 22 October 2026, 18:51 and 18:55)

Two live `live-now` rounds with the relay's `Server-Timing` header, run at the start of the evening slow
period. The first (18:51) stopped after one sample because ATP answered a board request with HTTP 503. The
owner approved one more round, which ran at 18:54:57 and finished all three samples. See the step 7 status
in [ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md).

**Result in one line:** neither round reached the slow state of step 7 (19:05, board waits of 1.5–3.7 s), so
they don't say whether ATP or the relay causes that slowdown. In the first round's short ATP slowdown, the
extra time was all in ATP's `upstream` time. The relay's share stayed small and flat.

- **Code:**
  - App: the existing Release simulator build of Verkeier `fa5833b` from the 20 October round, not rebuilt.
    Everything committed since is docs only.
  - Engine: MobilitéitKit `00078b6`.
  - Relay: `verkeier-relay` `f9c9f75`, deployed as version `aef3e2b5`.
- **Machine:** MacBook Air M4 with the iPhone 17 simulator, **on battery power** (55–56 %, discharging; the
  owner asked for the run to start now), Low Power Mode off, no other build or benchmark running. The Claude
  desktop app was the busiest process.

  | | Attempt 1 (18:51) | Attempt 2 (18:55) |
  |---|---:|---:|
  | 1-minute load at start | 3.61 | 1.96 |
  | CPU canary (transfer-walk build) | 2,119 ms | 1,941 ms |

  The canary was 2,053 ms on 20 October. The script did not wait for a quiet machine in either attempt.
- **ATP requests:** 53 in attempt 1 (45 responses captured; 8 were still in flight when the app stopped) and
  84 in attempt 2 (28 per sample), **137 in all**. Each attempt stayed under its `--request-budget 100`. The
  owner approved both.
- **Commands:** [`run.sh`](run.sh) for attempt 1 and [`run2.sh`](run2.sh) for attempt 2, which differs only in
  writing to `L2`. Each runs `Scripts/benchmark_routes.py --scenarios live-now --warm 1 --cold 1
  --maximum-limit-ms 0 --request-budget 100`. Compared with 20 October's script, they set `ALLOW_BATTERY=1`,
  wait at most 3 minutes for a quiet machine and then run anyway (they refuse only if Low Power Mode is on),
  and point `APP` at the old build.

## Attempt 1 (18:51): cut short by an ATP 503

| Step | Result |
|---|---|
| Priming sample | Finished: 27 boards, two passes, HTTP 200 for all of them |
| Warm sample | All 26 board requests sent. 18 had answered when the abort came: 17 × HTTP 200 and 1 × **503** |
| Cold sample | Not run |

- The 503 was for stop `000200417023`, lines 18 and 21 (the same board answered 200 in the priming sample). The
  response was 199 bytes, and no body file was captured. It carried `upstream;dur=659` and `edge;desc="LUX"`,
  so the relay had waited 659 ms for ATP's headers. That points to ATP, but I can't tell it apart from the
  Worker forwarding a status it made itself; the body would have said.
- The harness raised `Live benchmark stopped (quota, budget or capture failure)`, as designed. It failed
  before writing results, so `L1` has no `summary.json`. The completed priming sample was still in the
  simulator's temp folder, so I copied it out and added `process` and `relaySplit` the way the harness does
  (marked in the `recovered` field of the record in `L1/samples.json`). The warm sample has no result record;
  its figures come from the 18 captured responses and are biased low, because the 8 outstanding requests
  were most likely the slowest.

## Attempt 2 (18:55): all three samples

All 28 boards answered HTTP 200 in every sample, from the Cloudflare edge in Luxembourg (`LUX`) over h3. Each
sample ran one pass. Thermal state was nominal, there were no incomplete boards, and all 4 journeys were
fully live every time.

| Sample | Total, ms | Client server wait, median | ATP (`upstream`), median / max | Relay and network, median / max | Transfer, median |
|---|---:|---:|---:|---:|---:|
| Priming | 2,604 | 471 | 445 / 1,125 | 22 / 123 | 14 |
| Warm | 2,323 | 555 | 536 / 1,160 | 22 / 105 | 8 |
| Cold | 2,514 | 606 | 570 / 985 | 25 / 90 | 15 |

- **ATP is about 95 % of each board's server wait.** The relay hop plus network adds a median of 22–25 ms.
- **Slowest board:**
  - Priming: `000200417046` (1 line): ATP 1,125 ms, relay and network 16 ms, transfer 21 ms.
  - Warm and cold: Luxexpo `000200417050`, now **33 lines** (28 on 20 October), 126 KB. ATP 1,123 and 976 ms,
    relay and network 19 ms, transfer 109 and 105 ms.
- **The gate passes** in all three samples, at 2.3–2.6 s.
- **Machine-side stages:** the RAPTOR stage took 217–226 ms and `walkingPreparation` 232–319 ms.

## Attempt 1's priming sample, for comparison

| Sample | Total, ms | Client server wait, median | ATP (`upstream`), median / max | Relay and network, median / max | Transfer, median |
|---|---:|---:|---:|---:|---:|
| Priming (27 boards, two passes) | 3,632 | 864 | 801 / 1,517 | 73 / 224 | 14 |
| Warm (18 of 26 responses; no total) | – | 482 | 451 / 665 | 33 / 105 | 10 |

The priming sample's board fetch took 3,439 ms of the 3,632 ms. The slowest board was Luxexpo, at 1,748 ms
total: ATP 1,517 ms, relay and network 224 ms, transfer 6 ms. All 27 boards came from the edge in Luxembourg
over h2.

## Compared with the earlier rounds

| | 20 Oct 20:57 (fast) | 22 Oct 18:51, attempt 1 priming | 22 Oct 18:55, attempt 2 | 20 Oct step 7, 19:05 (slow) |
|---|---:|---:|---:|---:|
| Total, ms | 3,161 / 2,037 / 2,437 | 3,632 | 2,604 / 2,323 / 2,514 | 3,909–7,480 |
| Client server wait per board, median | 512–708 ms | 864 ms | 471–606 ms | 1.5–3.7 s |
| ATP (`upstream`), median | 402–604 ms | 801 ms | 445–570 ms | not measured |
| ATP (`upstream`), max | 794–910 ms | 1,517 ms | 985–1,160 ms | not measured |
| Relay and network, median | 70–117 ms | 73 ms | 22–25 ms | not measured |
| Relay and network, max | 186–282 ms | 224 ms | 90–123 ms | not measured |
| Transfer, median | 9–10 ms | 14 ms | 8–15 ms | 0.2–1.0 s |
| Edge, protocol | FRA, h3 | LUX, h2 | LUX, h3 | not measured |

**What the numbers say**

- **Attempt 2 was not slow.** ATP's median of 445–570 ms is inside 20 October's fast range (402–604 ms), and
  board waits of 0.5–0.6 s are far from step 7's 1.5–3.7 s. So this round doesn't answer the question the
  owner set. It was not quite as fast as 20:57 on 20 October, though: ATP's maximum was higher (985–1,160
  against 794–910 ms) and its bursts cleared more slowly (see below). Attempt 1's priming sample at 18:51
  was slower still.
- **The 18:51 slowdown was ATP's, and it passed within four minutes.** Against 20 October's priming sample,
  ATP's median was 33 % higher (801 against 604 ms) and its maximum 70 % higher (1,517 against 889 ms). The
  relay and network median was lower (73 against 104 ms). Four minutes later ATP was back at 445 ms. It's one
  episode, and it came with the only 503 of the night.
- **Relay and network has not grown in any sample.** Across all 129 captured responses of the evening it
  never exceeded 224 ms, while ATP's time ranged from 93 to 1,517 ms. Where the evening varied, ATP varied.
- **Relay and network was lower than on 20 October (22–73 against 70–117 ms).** Both rounds used the
  Luxembourg edge, where 20 October used Frankfurt, but attempt 1 at 73 ms was also on Luxembourg, with the
  machine at higher load (3.61 against 1.96). Part of this time is the Mac's, so I can't say how much comes
  from the edge. I haven't investigated.
- **Bursts cleared more slowly in the evening rush than at 20:57 on 20 October.** In each sample the first 24
  requests left within 3 ms of each other, so their `upstream` times are spread by ATP finishing them one
  after another:

  | Round | Spread of `upstream`, first 24 requests | Slope |
  |---|---|---:|
  | 20 Oct 20:57, priming / warm / cold | 216–871 / 71–612 / 168–809 ms | about 28 / 24 / 28 ms per board |
  | 22 Oct 18:55, priming / warm / cold | 127–1,125 / 96–1,160 / 106–985 ms | about 43 / 46 / 38 ms per board |
  | 22 Oct 18:51, priming | 204–1,310 ms | about 48 ms per board |

  The slope is a more sensitive sign than the median: it was 40–90 % steeper tonight, and steepest at 18:51,
  where the 503 also appeared. A board's `upstream` time is mostly its place in that spread. It doesn't follow
  its line count or size, except that the widest board (Luxexpo) is usually among the slowest. That looks like
  ATP working through the burst partly one board after another, at a rate that drops under load, and the time
  of day may be why. This is a reading of the timings across three rounds, not something I tested. A test
  would need single-board requests, which are not approved.
- **Passes:** attempt 2 ran one pass in each sample. Attempt 1's priming sample ran two. On 20 October all
  three ran two, because a transfer-stop board had not been fetched in discovery (see
  [that write-up](../server-timing-2026-10-20/README.md#why-each-sample-ran-two-passes)). I didn't trace
  either of tonight's cases.
- **The 503 fits step 7's rate-limit guess but doesn't test it.** Step 7's slow rounds followed 162 requests
  within about a minute. The 503 came after 45 responses in about 4 seconds. One error in 137 requests is not
  a pattern.

## Limits

- **No slow period was measured.** The question stays open until a round runs when board waits are above
  1.5 s. I can't tell in advance when that is, and a new round needs a new approval.
- **The relay times only the wait for ATP's response headers.** Body transfer is streamed and isn't split.
  Transfer was small here (medians of 8–15 ms), so it isn't hiding anything this time.
- **Three samples and a partial one** can't give spreads. Replay timings, if used, vary by 10–20 %.

## Files

| File | Content |
|---|---|
| `L2/samples.json` | Every attempt 2 sample, with `relaySplit` and each request's `metrics.serverTiming` |
| `L2/summary.json`, `L2/transport.json`, `L2/optimisation.json` | Medians, response metadata (no bodies), and the CPU canary |
| `L1/samples.json` | Attempt 1's priming sample only, recovered by hand (see above) |
| `L1/transport.json`, `L1/optimisation.json` | The 45 captured responses and the CPU canary of attempt 1 |
| `L1/aborted.json`, `L1/harness-traceback.log` | Why attempt 1 stopped, with its request count, and the harness's traceback |
| `run.sh`, `run.log`, `run2.sh`, `run2.log` | The scripts and their output |

`L1` has no `summary.json`: the harness writes it only after a series completes. The raw bodies
(`L1/network`, `L2/network`) and the app build are in `~/Developer/Verkeier-captures/server-timing-2026-10-22/`
and `~/Developer/Verkeier-captures/server-timing-2026-10-20/app/`, outside git.
