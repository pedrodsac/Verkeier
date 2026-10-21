# CAND-29, transfer-first discovery ordering: offline evaluation (Tuesday 20 October 2026, 21:40–22:05)

This is the offline evaluation of CAND-29 ([plan §4.5](../../ROUTING_SPEED_PLAN.md)) on the recorded ATP captures,
with no ATP request. **The candidate cannot be replayed on any capture**: half to two thirds of the boards it asks for
were never recorded, so every candidate replay aborts with `missing-replay-query`. What this folder does show,
without any response, is *which boards each ordering would fetch*, and that shows CAND-29 as specified does not fetch
the board that caused the 20:57 second pass.

- **Code:** scratch copies only. Engine `00078b6` (`git archive`) plus [`engine.diff`](engine.diff); app `fa5833b`
  (`git archive`) pointed at the scratch engine. Nothing in `~/Developer/MobilitéitKit` or any tracked file of this
  repo was written, nothing was committed or pushed.
- **ATP requests:** 0. The replay client points at `recorded-atp.invalid`.
- **Machine:** MacBook Air M4, iPhone 17 simulator, **on battery power**, Low Power Mode off, 1-minute load 3–9 (a
  build and other sessions were running between replays). CPU canary (transfer-walk build) 1.9–2.3 s in 10 of 11
  control runs, 2.87 s in one (s7-L3). Replay timings are very stable here (±2 % between repeats), but the machine
  was not as quiet as for a timing run.
- **Switches** (read in the engine with `ProcessInfo`, so one build serves every arm; passed with
  `SIMCTL_CHILD_…`):
  - unset: control, behaves as `00078b6`;
  - `CAND29=1`: the plan's ordering;
  - `CAND29=cap4`: the same plus at most 4 destination-walkable boards;
  - `CAND29=arr`: **exploratory, not in the plan**, see below;
  - `PASS_DEBUG=1`: `ROUTING_DEBUG` log lines (the `PassDebug` helper of the 20:57 investigation, now gated).

## What was implemented

[`engine.diff`](engine.diff), new file `JourneyPlanningSession+TransferFirst.swift` and edits in
`discoveryRealtimeTargets` / `realtimeFrontier` (`JourneyPlanningSession+Realtime.swift`):

- Which stops qualify is unchanged: the optimistic walking-chain envelope (`allowWalkingChains: true`) and the same
  departure test.
- The order uses `Raptor.DestinationReachability(snapshot:egressStops:maxRides:)` with `maxRides =
  maximumRealtimeRides` (4 for `maxTransfers = 3`) and no walking chains, which is exactly what `Raptor.search`
  builds and caches in `PreparationCache.destination` for its executable rounds. A stop's rank is the first level
  that contains it: 1, 2, 3, then 0 (destination walkable) last, then "not reachable" after that.
- Ties break as before: for access stops walk seconds, then stop id; for later waves distance to the destination,
  then arrival, then id. `prefix(8)` per wave and the 24-board total are unchanged.
- The build costs 0.5 ms per discovery (measured in the log), so no sharing with the RAPTOR cache is needed.
- `cap<N>`: stops of rank 0 (and "not reachable") are admitted until N boards have been planned.
- `arr` (exploratory): equal ranks break by the earliest arrival at the stop, before distance.

## Results

### 1. The control replays reproduce the live captures exactly

Scratch build, `CAND29` unset, `--replay-latency`, one replay per capture (three for `st-L1` and `s7-L1`).
`unfilteredJourneys`, `networkRequests`, `responseBytes` and boards covered equal the live capture in every sample;
`journeys`, `options`, `recommendedOption` and `realtimeCoverage` differ only through the wall-clock option
visibility rule (the replays ran 1–28 hours after the captures). `--replay-approximate` was on, but no
`approximate-queries.json` was written, so no control query was approximate.

| Capture | Time | Live passes | Replay passes | Requests | Decoded MB | Live total, ms (prim / warm / cold) | Replay median, ms |
|---|---|---:|---:|---:|---:|---|---|
| `st-L1` (server-timing) | 20:57 | 2, 2, 2 | 2, 2, 2 | 26 | 9.07 | 3,161 / 2,037 / 2,437 | 2,333 / 2,158 / 2,355 |
| `s7-L1` (step 7) | 18:52 | 1 | 1 | 26 | 15.6 | 2,914 / 2,141 / 2,562 | 2,323 / 2,110 / 2,301 |
| `s7-L2` | 19:05 | 1 | 1 | 27 | 14.4 | 5,490 / 4,792 / 4,629 | 4,492 / 4,238 / 4,385 |
| `s7-L3` | 19:06 | 1 | 1 | 27 | 14.4 | 4,959 / 7,480 / 3,909 | 7,467 / 7,256 / 7,362 |
| `c28-now` (10-19) | 18:44:01 | 1 | 1 | 27 | 15.7 | 3,131 | 2,909 |
| `c28-rev` | 18:44:55 | 1 | 1 | 29 | 18.1 | 3,101 | 2,984 |
| `c28-esch` | 18:45:49 | 1 | 1 | 25 | 10.4 | 2,187 | 2,089 |

Source: [`control-baseline.json`](control-baseline.json). The replay uses the recorded server waits, so it follows
the capture's ATP speed (`s7-L2`/`s7-L3` were the slow 19:05 rounds), not this machine's.
**`st-L1` is the only capture with a second pass**; the other six already run one pass with CAND-28 in the engine.

### 2. CAND-29 asks for boards that were never recorded

Both ordering arms were replayed on every capture (priming sample, `--replay-approximate`, `PASS_DEBUG=1`). Every one
of the 21 candidate runs (7 captures × `1`, `cap4`, `arr`) aborted with `missing-replay-query`
(`aborted.json`); no candidate arm produced a result, a pass count or a timing. The discovery plan is logged
before the first request, so it is still known ([`plans/`](plans/), [`plan.json`](plan.json),
[`plan-analysis.txt`](plan-analysis.txt)). The unrecorded queries of each aborted batch are in
[`missing-queries/`](missing-queries/).

| Capture | Boards shared with control | CAND-29 queries recorded / asked | Unrecorded queries |
|---|---:|---:|---:|
| `st-L1`, `s7-L1`, `s7-L2`, `s7-L3`, `c28-now` | 8 of 24 | 8 / 24 | 16 each |
| `c28-rev` | 12 of 24 | 12 / 24 | 12 |
| `c28-esch` | 14 of 24 | 12 / 24 | 12 |

- The shared boards are mostly origin-side access stops (6 of 8) plus Mathias Tresch and Biechelchen. The other 16
  (10–12 on `c28-rev`/`c28-esch`) are stops near the destination that no run asked for before.
- `cap4` chose exactly the same 24 stops as `1` on all seven captures. Destination-walkable stops sort last, and
  there are at least 24 better candidates in every wave, so the cap never binds.
- **The harness rule holds:** a stop that was never recorded cannot be replayed, and I did not substitute or fake
  such boards. Covering CAND-29's boards needs a live capture of them (16 requests per capture for the first batch
  alone), and a replay also needs the later waves that its different data would trigger.

### 3. What CAND-29 would fetch (plan-level, no responses)

**The tiers are huge, so the old tie-break still decides.** Candidates of discovery wave 1 / wave 2, by the
one-batch rank (zero = destination walkable):

| Capture | Wave 1: rank 1 / 2 / zero (of) | Wave 2: rank 1 / 2 / 3 / zero (of) | Héienhaff P+R T1 position wave 1 / 2 |
|---|---|---|---|
| `st-L1` | 269 / 39 / 9 (317) | 960 / 405 / – / 39 (1,404) | 102 / 196 |
| `s7-L1` | 283 / 46 / 9 (338) | 1,076 / 480 / – / 43 (1,599) | 103 / 221 |
| `s7-L2` | 269 / 42 / 9 (320) | 1,068 / 491 / – / 41 (1,600) | 99 / 217 |
| `s7-L3` | 271 / 42 / 9 (322) | 1,071 / 491 / – / 41 (1,603) | 99 / 217 |
| `c28-now` | 283 / 45 / 9 (337) | 1,090 / 496 / – / 44 (1,630) | 103 / 223 |
| `c28-rev` | 326 / 238 / 4 (568) | 494 / 1,221 / 31 / 31 (1,777) | zero-ride, 566 / 1,775 |
| `c28-esch` | 166 / 326 / 10 (502) | 166 / 1,341 / 351 / 5 (1,863) | not a candidate / 1,065 |

- With the plan's ordering, **Héienhaff P+R T1 (`000200508005`) is never fetched in discovery** on the 20:57 capture.
  It does rank ahead of the 9 (wave 1) and 39 (wave 2) zero-ride stops, as the plan says, but 269 other rank-1
  stops precede it by distance to the destination (position 102 of 317; each wave takes 8).
  So the second pass of 20:57 is not avoided. This is inferred from the plan: a replay of the candidate is
  not possible, and the data pass 0 would see could change which journeys it picks.
- **What changes instead:** the control's later waves are mostly destination-walkable stops (14 of 16 on the five
  `live-now` captures, 12 of 16 on `c28-rev`, 10 of 16 on `c28-esch`). CAND-29 replaces *all* of them with rank-1
  stops (0 zero-ride boards on every capture), still the ones closest to the destination: Kirchberg, Dommeldange,
  Weimerskirch, Neudorf, Cents. The access wave also changes (rank-1 stops `000200508009`, `000200503001` instead of
  the rank-2 stops `000200508010`, `000200503012`).
- **Late boards:** boards that the control's speculative completion fetches outside discovery (the CAND-28 hub
  boards): CAND-29 covers Luxexpo `000200417050` on five of the six captures that need it (all but `c28-rev`; `c28-esch`
  needs none) and never Héienhaff `000200508016`. The only board asked after pass 0 in any capture is Héienhaff P+R in `st-L1`
  (control: outside discovery; CAND-29: outside; `arr`: inside).

Example, `st-L1`, discovery boards (wave 1, then wave 2) per arm; [`plans/st-L1-*.txt`](plans/):

| Arm | Wave 1 | Wave 2 |
|---|---|---|
| control | Simone de Beauvoir, Luxexpo Entrée Sud, Poutty Stein, Neudorf Kapell, Mathias Tresch, Dauschbuer, Biechelchen, Cents C. de Tornaco | Konrad Adenauer ×2, Coudenhove-Kalergi, Avalon, Albert Borschette, Universitéit, Sichegronn, St Exupéry (all Kirchberg, all zero-ride) |
| `CAND29=1` | Mathias Tresch, Biechelchen, Van der Meulen, Laangegronn, Arthur Knaff, Contournement, Hugo Gernsback, Parc de l'Europe | Léon Thyes, Rehazenter, Europaparlament, Niedergrünewald, Mäertesbuer, Gare routière Luxexpo, Prince Félix, Luxexpo |
| `CAND29=arr` | Laangschib, Rue du Golf, Mënsterbësch, **Héienhaff P+R**, Héienhaff, Parishaff, Senningen ×2 | Senningen, Niederanven ×2, Ernster ×2, Findel airport ×2, Lou Hemmer |

### 4. The exploratory `arr` arm

Not part of the plan. It shows the other end of the choice: break rank ties by arrival, before distance.
It does fetch Héienhaff P+R in discovery on `st-L1` (the missing board, post-pass board 1 of 1), and Héienhaff
`000200508016` on `c28-now` and `s7-L1`. But its wave 1 and 2 are all next to the origin (Senningerberg, Senningen,
Niederanven, Findel) and none is near the destination, so Luxexpo and the destination-side boards are gone (speculative
boards covered 0 of 3 on `s7-L2`/`s7-L3`). It shares only 6–8 boards with the control and is equally unreplayable
(16–18 unrecorded queries per capture). I do not suggest it as a design; it shows that distance and arrival are both
too blunt, and that the choice needs a signal for *transfer* stops.

## Verdict against the plan's step 5 acceptance (§5)

| Criterion | Status |
|---|---|
| One authoritative pass in most runs (≥ 2/3) | **Not measurable offline.** Baseline: 1 pass in 6 of 7 captures already (CAND-28). The one two-pass capture (`st-L1`) is *not* fixed by the specified ordering (Héienhaff P+R not in discovery; inferred) |
| `networkRequests` ≤ +20 % | **Not measured.** Discovery stays capped at 24 boards, so the count should stay near 26–29 (inference) |
| `responseBytes` not higher | **Not measured.** The boards differ (10–14 destination-walkable boards replaced), so bytes and server waits are unknown. The plan's premise (destination-side boards are largest and slowest, 75 % of bytes) would have to be re-measured for the new set |
| Every shown ride has a fresh or attempted live board (INV-6) | Holds by construction (completion of selected rides is unchanged); not verified by a run |
| Live coverage of shown journeys not lower; journey sets reviewed | **Not possible** without results |
| No validator rejections | Not measured |

**Verdict:** CAND-29 as specified is not shown to meet step 5 and, from the discovery plans, should not be expected to
remove the 20:57 second pass. It is not worth spending ATP requests on in this form. Only the control baseline
(section 1) is a measurement; everything in section 3 is a statement about which boards would be asked.

## Limits and what still needs a live run

- **Why no candidate timings:** none of the 21 candidate runs completed, so there are no A/B medians. The control
  runs were repeated three times on `st-L1` and `s7-L1` (spread ±2 %) so that a later live A/B has a replay baseline.
- **Which boards the pass-0 picks need depends on the data discovery returns.** The coverage statements in section 3
  use the control's pass-0 needs. A different discovery set could change pass 0's journeys.
- **Only one capture has the two-pass problem.** Any new ordering rule tuned on it risks overfitting; more
  two-pass evenings (a live round in a period like 20:57) would be needed to find the pattern.
- **Live needs (owner approval for ATP):**
  - A live A/B of any ordering that can be replayed only after being captured: 3 routes × 2 arms × 1 rep is about
    165 requests, 3 reps about 450 (plan §7 item 1b); a union capture holding both arms' queries, taken within a few minutes, would let the
    replays compare passes, results, bytes and timings. A union capture must be live in one session; fetching
    the missing boards later returns different realtime data than at the capture's epoch.
  - Not worth it for `CAND29=1` as is, unless the owner wants a measured confirmation that it leaves the second
    pass in place.
- **Untested directions, only if CAND-29 is pursued** (each can be checked at plan level for free with this
  harness before any live run, using the board that pass 0 asked for after the fact): a signal for transfer stops
  such as hubs (number of distinct lines departing), or the transfer stops of the preliminary journeys beyond the six
  selected; or reserving a few of the 24 slots for such stops while keeping today's order for the rest.
- Not measured: the iPhone, and `--replay-approximate` boards for the control (none were needed).

## Files

| File | Content |
|---|---|
| `engine.diff` | Scratch engine against `00078b6`: CAND-29 switches, the gated `PassDebug` helper and log lines (no injection). Applied to scratch copies only, committed nowhere |
| `plan.json`, `plan-analysis.txt` | Discovery plans, tier sizes, shared boards, recorded and unrecorded queries, board coverage per capture and arm |
| `plans/<capture>-<arm>.txt` | Discovery lines from the diagnostic logs (access and waves with names and ranks, frontier candidates, Héienhaff position, pass and completion lines, aborts) |
| `missing-queries/` | The unrecorded queries of each aborted batch (`1` and `arr`; `cap4` is identical to `1`) |
| `control-baseline.json` | Live and replayed control: passes, requests, bytes, totals, canary |
| `tools/` | `replay.sh` (one replay), `captures.sh`, `plan_runs.sh`, `cap_runs.sh`, `base_runs.sh`, `analyze_plan.py`, `compare.py`. Paths are those of the scratch directory of this session |

The raw replay output and the scratch builds are in the session's scratchpad, outside git:
`/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/a26d6e08-38cf-4a43-aeea-70a2e41c82cd/scratchpad/`
(`runs/plan`, `runs/base`, `engine`, `dd`).
