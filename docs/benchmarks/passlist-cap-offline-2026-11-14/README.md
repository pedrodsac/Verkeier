# Passlist cap (`passlistMaxStops`), offline check (14 and 15 November 2026)

ATP's `departureBoard` takes a `passlistMaxStops` parameter that the engine never sends. Passlists are 87 % of
board bytes. I capped the recorded passlists of eight live captures at K stops, replayed each capture with the
original bodies and with every capped set, and compared the routing results. No ATP request was sent.

**Result for the first K stops:** with two small engine changes (15 November, [below](#fix-and-replay-sunday-15-november)),
a cap of 10 stops changed no result in 18 of 18 samples on the old engine and 4 of 4 on the current one. It saves
43 % of decoded bytes, and 85 % together with the CAND-12 (a) field trim. Without the changes, K = 10 changed 8 of
18 samples and cost one shown bus its 5-minute delay. A cap of 20 needs no change but saves only 15 %.
**The live probe (15 November, [`probe/`](probe/README.md)) showed that ATP keeps the terminus:** a capped passlist
is the board stop, the next K − 2 stops and the last stop. **Replayed in that shape**
([below](#terminus-kept-sunday-15-november-evening)), K = 10 needs the merge clamp and a new gap rule (stops ATP
leaves out keep the last reported delay, with no 30-minute horizon). With both, every shown result stayed the same:
20 of 21 samples were identical on the old engine and 4 of 4 on the current one, and the one exception is a
tie that doesn't show. It saves 44 % decoded and 45 % brotli, or 85 % and 77 % with the field trim. Unchanged,
5 of the 8 captures lost buses' live data, and one shown bus lost its 4:20 delay. **The real engine change**
([below](#the-engine-change-sunday-15-november-night)) reproduces this on the current engine: 4 of 4 samples
identical with capped passlists and 4 of 4 with whole ones. Trip detail asks for whole passlists, so it keeps its
live times. The app pins it (`ef2c4c9`), with the stop board on the same cap; its tests pass.

The sections up to "Fix and replay" describe the 14 November replay on unchanged code; "Terminus kept" is the
replay in ATP's real shape.

- **Code:** Verkeier `4911ff0` with MobilitéitKit `a152c0f` (the current pin), Release simulator build with
  `ENABLE_CODE_COVERAGE=NO` ([`BUILD.txt`](BUILD.txt)).
- **Timetable:** generation 5 (`gtfs-20261007-20261212.zip`) from the Mac app container. It holds all 30 trips
  of the captured journeys. Journey IDs carry `g5:` where the captures carry `g1:`; otherwise every original
  replay reproduced its live capture's journeys.
- **Captures:** the eight used for CAND-12 (a): `st-L1`, `s7-L1`, `s7-L2`, `s7-L3` (20 Oct), `c28-now`, `c28-rev`,
  `c28-esch` (19 Oct), `st22-L2` (22 Oct). They were copied from the 29 October Time Machine backup into a session
  scratchpad, because `~/Developer/Verkeier-captures` no longer exists.
- **Replay:** `--replay-latency --replay-approximate --request-budget 0`. The current engine asks for some boards
  with a different line filter than the October engine did. Approximate mode builds those from the recorded board
  of the same stop and window: 2–15 queries per run, the same in every arm. One run per capture and arm, 18 samples
  per arm. The load wait was raised from 6 to 10 during the sweep, because only results are compared.
- **Assumption:** every recorded passlist starts at the board stop, so the cap keeps the board stop and the next
  K − 1 stops. ATP's actual `passlistMaxStops` behaviour is **not verified**; that needs one live request.

## Results

Decoded MB of all bodies after capping (change from the original), then the samples whose results were identical.
Results are the harness's result fields: `unfilteredJourneys`, `journeys`, `options`, `recommendedOption`,
`realtimeCoverage`, `matchingRejections`, `displayedLegs`, `supplementalOptions`, `canLoadEarlier`, `canLoadLater`.

| Capture | Bodies | Original MB | K = 5 | K = 10 | K = 20 | K = 10 + fields |
|---|---:|---:|---|---|---|---|
| `st-L1` | 78 | 27.2 | 10.8 (−60 %), 0/3 | 15.8 (−42 %), 3/3 | 23.8 (−13 %), 3/3 | 4.2 (−85 %), 3/3 |
| `s7-L1` | 78 | 46.8 | 18.2 (−61 %), 0/3 | 26.7 (−43 %), 0/3 | 40.2 (−14 %), 3/3 | 7.2 (−85 %), 0/3 |
| `s7-L2` | 81 | 43.1 | 16.5 (−62 %), 0/3 | 24.1 (−44 %), 3/3 | 36.7 (−15 %), 3/3 | 6.5 (−85 %), 3/3 |
| `s7-L3` | 81 | 43.5 | 16.7 (−62 %), 0/3 | 24.4 (−44 %), 3/3 | 37.1 (−15 %), 3/3 | 6.6 (−85 %), 3/3 |
| `c28-now` | 27 | 15.7 | 6.1 (−61 %), 0/1 | 8.9 (−43 %), 1/1 | 13.4 (−14 %), 1/1 | 2.4 (−85 %), 1/1 |
| `c28-rev` | 29 | 18.1 | 6.9 (−62 %), 0/1 | 10.2 (−43 %), 0/1 | 15.6 (−14 %), 1/1 | 2.8 (−85 %), 0/1 |
| `c28-esch` | 25 | 10.4 | 3.5 (−67 %), 0/1 | 5.2 (−50 %), 0/1 | 7.4 (−29 %), 1/1 | 1.2 (−88 %), 0/1 |
| `st22-L2` | 84 | 48.9 | 19.3 (−61 %), 3/3 | 28.1 (−43 %), 0/3 | 42.2 (−14 %), 3/3 | 7.5 (−85 %), 0/3 |
| **All** | 483 | 253.8 | −61 %, **3/18** | −43 %, **10/18** | −15 %, **18/18** | −85 %, **10/18** |

- **Wire size** (brotli -q 4 of all bodies, MB): original 8.68, K = 5 3.16, K = 10 4.69, K = 20 7.25,
  K = 10 + fields 1.95. The recorded wire total was 11.59 MB, so the relay's encoding is weaker than brotli 4, but
  the ratios should carry over.
- **Per search** (median decoded bytes): 14.5 MB originally. K = 20 saves 2.2 MB, K = 10 saves 6.4 MB, and
  K = 10 + fields saves 12.3 MB.
- **K = 15 and K = 30** were trimmed but not replayed. K = 30 saves 2 %. For K = 15 the chronology check below
  predicts differences in `c28-esch`, `c28-rev` and `s7-L1`.
- **Internal counters change in every arm**, K = 20 included: `predictedEvents`, `invalidJourneys`,
  `duplicatesSuppressed` and `walkingRequests`. The engine does slightly different work with fewer reported
  stops, even when it shows the same result.
- **Total time** fell in most capped samples, but the replay replays the recorded server wait, so this says
  nothing about ATP answering faster. Earlier rounds saw ATP's wait grow with decoded size. Whether a smaller
  passlist shortens that wait can only be measured live.

## What changed

- **K = 10, 7 samples (`s7-L1`, `c28-rev`, `st22-L2`):** only `matchingRejections` changed, by a new
  `invalidTripTimeline` count of 1–5. No journey or shown time changed.
- **K = 10, `c28-esch`:** line 651 at Esch-sur-Alzette, Gare routière was shown leaving at its scheduled 18:54:40,
  `live`, instead of 18:59, `delayed`. The board reported the 5-minute delay; the capped arm lost it.
- **K = 5:** observed arrivals became estimated (line 25 at `000200417050` and `000200417033`, line 321 at
  `000200508002`, 20 s earlier), and `c28-now`'s `journeys` (leg times) changed. Only `st22-L2` stayed identical.
- **The field trim added nothing:** K = 10 + fields gave exactly K = 10's results, as CAND-12 (a) predicts.

## Why K = 10 fails: the 30-minute estimate horizon

`patch(for:)` in `HafasRealtimeRoutingProvider+Events.swift` builds a patch for the whole trip. After the last
reported stop, it gives each stop that stop's delay for 30 minutes of scheduled time, then the scheduled time.
With a full passlist every later stop is reported, so the horizon never matters. With a capped passlist, a delayed
trip that runs on more than 30 minutes past the cut falls back from "scheduled + delay" to "scheduled". If the
delay is longer than the gap between two stops, the patch goes back in time, and the engine drops the board row's
whole patch as `invalidTripTimeline`.

[`tools/chronology_check.py`](tools/chronology_check.py) counts such rows in the recorded bodies:

| Capture | K = 5 | K = 10 | K = 15 | K = 20 |
|---|---:|---:|---:|---:|
| `c28-esch` | 9 | 8 | 2 | 0 |
| `c28-now` | 4 | 0 | 0 | 0 |
| `c28-rev` | 11 | 6 | 1 | 0 |
| `s7-L1` | 18 | 12 | 3 | 0 |
| `s7-L2` | 10 | 0 | 0 | 0 |
| `s7-L3` | 12 | 0 | 0 | 0 |
| `st-L1` | 6 | 0 | 0 | 0 |
| `st22-L2` | 27 | 21 | 0 | 0 |

At K = 10, the four captures with such rows are exactly the four that changed. The four without any were
identical. At K = 20 there are none, and nothing changed. I haven't traced which row cost line 651 its delay.

## How deep the shown journeys go

Journey IDs record each ride's boarding and alighting positions. The 84 distinct rides of the live captures go
1–6 stops, except six rides of 20 stops on `c28-esch`. So K = 10 covers every ride on the Gromscheed ↔ Kirchberg
captures, which are 7 of the 8. That says little about long cross-country bus rides.

## Fix and replay (Sunday 15 November)

### The two changes

Both are in [`engine-experiment.diff`](engine-experiment.diff). They apply only when the environment variable
`ROUTING_PASSLIST_CAP` is set (to K); without it every build runs its engine's unchanged code. The two changed
files are identical in `a152c0f` and `d98fb57`.

1. **Estimate horizon** (`HafasRealtimeRoutingProvider+Events.swift`, `patch(for:)`): when a board row's passlist
   has K stops, the stops after its last reported stop keep that stop's delay to the end of the trip, instead of
   falling back to the timetable after 30 minutes. Every board's own patch then stays chronological.
2. **Merge clamp** (`RealtimeTripPatch+Merging.swift`, `merging(_:)`): the merged patch gets the same
   minute-precision clamp as a single board's patch (`RealtimeTimeline.constrainingMinutePrecision`) before its
   chronology check.

The first change alone wasn't enough. A trip's patch is merged from every board that lists it, stop by stop: a
report beats an estimate, and between two estimates the later observation wins. In `c28-esch`, line 651 is
listed by eight boards. With K = 10, the Esch, Gare routière board estimates the arrival at Dudelange, Rue de la Rivière
as 19:12:55 + 4:10 = 19:17:05, and that stop's own board reports the departure as 19:17:00, to the minute. The merged patch goes back 5 seconds, and the merge then keeps one board's whole patch and drops the
other. When it kept a Dudelange board's patch, which has only timetable times before Dudelange, the bus at Esch
showed 18:54:40 instead of 18:59. Which patch survives depends on which board was observed last, so repeated runs
of the same capture gave different results. With full passlists every stop is reported, so this mix rarely
arises.

### Old engine (`a152c0f`), all 18 samples

The replay used the October captures on the engine they were recorded with (Verkeier `4911ff0`). Results
identical to the original replay (unchanged engine, no cap):

| Cap | Decoded | brotli | Unchanged (14 Nov) | Horizon change only | Both changes |
|---|---:|---:|---|---|---|
| K = 20 | −15 % | −16 % | 18/18 | – | – |
| K = 15 | −28 % | −30 % | not replayed | 17/18 | **18/18** |
| K = 10 | −43 % | −46 % | 10/18 | 17/18 | **18/18** |
| K = 10 + fields | −85 % | −78 % | 10/18 | 17/18 | **18/18** |
| K = 5 | −61 % | −64 % | 3/18 | 10/18 | 11/18 |

`c28-esch` was run four times per arm, and the table above counts the first run. Line 651 at Esch kept its delay
in this many of the four runs:

| Cap | Horizon change only | Both changes |
|---|---|---|
| K = 10 | 0 of 4 | 4 of 4, all identical to the original |
| K = 10 + fields | 0 of 4 | 4 of 4, all identical |
| K = 5 | 1 of 4 | 4 of 4, all identical |

With both changes, the 7 samples that differ at K = 5 differ only in a label: line 25's arrival is marked
"estimated" instead of "observed", at the same time (`c28-now`, `s7-L1`, `st-L1`). Those rides alight more than
four stops after the board stop, beyond a 5-stop passlist. `c28-esch`'s 20-stop ride stayed identical even at
K = 5, because the Dudelange boards report its last stops.

### Current engine (`d98fb57`)

The current engine asks six of the eight captures for boards they don't hold, at transfer stops the October engine
never queried (`000200508016`, `000200417012`, `000200417066` for T1). Approximate replay can't build those, so
those runs abort with `missing-replay-query` in every arm, the original one included. Only `s7-L1` (3 samples)
and `c28-esch` (1) replay (Verkeier `eed8d9e`).

| Cap | Unchanged | Horizon change only | Both changes |
|---|---|---|---|
| K = 20 | 4/4 | – | – |
| K = 15 | – | – | **4/4** |
| K = 10 | 0/4 | 3/4 | **4/4** |
| K = 10 + fields | – | 3/4 | **4/4** |
| K = 5 | – | 0/4 | 1/4 (line 25 label, as above) |

With the horizon change only, `c28-esch` at K = 10 kept the delay but showed the 20-stop ride's arrival as
estimated, 5 seconds early; at K = 10 + fields it lost the delay. On this engine the original replay of `s7-L1`
finds different journeys than its live capture did, so the arms are compared with this engine's own original
replay.

## Terminus kept (Sunday 15 November, evening)

The live probe showed that a capped passlist is the board stop, the next K − 2 stops and the terminus. The sets
were trimmed again in that shape (`trim_passlist.py --keep-last`) and replayed on both engines, offline as before.

### What the terminus changes in the engine

The terminus is reported, so the 15 November horizon change never applies: no stop lies after the last reported
one. What is new is a gap between stop K − 2 and the terminus. The unchanged engine estimates gap stops with the
last reported delay for 30 minutes and then falls back to the timetable. A delayed bus whose gap runs past 30
minutes then gets a patch that goes back in time, and the whole patch is dropped (`invalidTripTimeline`).

ATP's own prognoses for the gap are almost always the last kept stop's delay carried forward
([`tools/gap_estimate_check.py`](tools/gap_estimate_check.py), all eight captures, in ATP's minute times):

| Rule for a gap stop | Matches ATP's prognosis |
|---|---:|
| Delay at stop K − 2, carried forward | 98.9 % (49,557 of 50,130 stop times in 2,422 distinct passlists) |
| Delay interpolated from stop K − 2 to the terminus | 94.9 % |

360 of those stop times are more than 30 minutes after stop K − 2 with a delay that isn't zero, where the
horizon throws the delay away.

### The gap rule

[`engine-gap-rule.diff`](engine-gap-rule.diff), on top of the two earlier changes and behind
`ROUTING_PASSLIST_GAP=1` (with `ROUTING_PASSLIST_CAP=10`): in a capped passlist, a stop ATP left out keeps the
preceding reported delay, without the 30-minute horizon. Arms:

| Arm | Set | Flags | Engine code |
|---|---|---|---|
| `k10last` | K = 10, terminus kept | none | unchanged |
| `k10lastfix` | same | `CAP=10` | merge clamp (the horizon change is a no-op) |
| `k10lastgap` | same | `CAP=10`, `GAP=1` | merge clamp and gap rule |
| `f10lastgap` | same plus the CAND-12 (a) field trim | `CAP=10`, `GAP=1` | merge clamp and gap rule |

### Results

Samples with results identical to the original replay. The old engine has 21: the 18 above, plus three more
`c28-esch` repeats (`f10lastgap` ran once, 18 samples).

| Arm | Old engine (`a152c0f`) | Current engine (`d98fb57`) |
|---|---|---|
| `k10last` | 9/21 | 0/4 |
| `k10lastfix` | 9/21 | 0/4 |
| `k10lastgap` | **20/21** | **4/4** |
| `f10lastgap` | **17/18** | – |

- **Unchanged engine:** every capture except `st-L1`, `s7-L2` and `s7-L3` lost 1 to 6 trips' realtime patches
  as `invalidTripTimeline`. Line 651 at Esch-sur-Alzette, Gare routière was shown at its timetable time instead of
  4:20 late in 3 of 4 old-engine runs and in the current-engine run. This is the merge failure described above.
- **Merge clamp only:** line 651 kept its delay in all five runs, but the dropped patches stayed (5 in
  `c28-esch`, 1 to 3 elsewhere). In these samples they changed no journey, but each one is a bus shown without
  its live data.
- **Merge clamp and gap rule:** `matchingRejections` equal the original everywhere, and every shown journey,
  time, source and status is identical. The one remaining difference is in `c28-rev`, and it doesn't show.

**The `c28-rev` difference is a tie, not a lost journey.** The Kirchberg, Konrad Adenauer → Gromscheed journey
(line 16, then line 29 to Senningerberg, Charlys Statioun, then a walk) is found either ending at Charlys
Statioun or with a footpath to Senningerberg, Breedewues. Both have the same legs, walk, arrival and live status.
The journey ID includes the end stop, so the comparison counts it as lost and gained. All four terminus arms pick
Charlys Statioun, the unchanged engine included; the original and every prefix arm pick Breedewues. Bisecting
the 564 capped passlists ([`tools/bisect_tie.py`](tools/bisect_tie.py), 13 replays) found the single cause: line
25 from Kirchberg, Coudenhove-Kalergi at 18:48, which is on time throughout. ATP floors every time to the minute
and the timetable has seconds: the last kept stop is reported at 18:58 against a timetable time of 18:58:50, so
the engine carries a delay of −50 seconds through the gap. Its gap stops land up to 50 seconds before ATP's own
reports (Neudorf, Carrières 18:59:10 against ATP's 19:00), and that moves the tie. Restoring Bus 327's passlist,
the only one in this capture whose gap prognosis ATP changes mid-gap (+3 minutes after stop 9), didn't move it.

### Bytes

| Set | Decoded | brotli -q 4 |
|---|---:|---:|
| K = 10, first K stops (14 Nov) | −43.5 % | −46 % (4.69 MB) |
| K = 10, terminus kept | −44.2 % | −45 % (4.74 MB) |
| K = 10, terminus kept, plus fields | −85.2 % | −77 % (1.96 MB) |

Of 253.8 MB decoded and 8.68 MB brotli originally. Decoded falls slightly more with the terminus kept because
the cut drops the stop K − 1 instead of the last one, and a terminus row is shorter. The single board in the live
probe fell by 69 %, as its passlists are longer than average.

## The engine change (Sunday 15 November, night)

Both changes are now real MobilitéitKit code, committed as `02e17cf` on the engine's `main` (a fast-forward
from `d98fb57`; pushed, and pinned by the app in `ef2c4c9`)
([`engine-change.diff`](engine-change.diff)):

- **Request:** `HafasDepartureBoardRequest.passlistMaximumStops` is sent as `passlistMaxStops`, only with
  `passlist=1`. Every routing board fetch and cache lookup goes through one `routingBoardRequest(...)`, which
  sends 10 (`HafasRealtimeRoutingProvider.routingPasslistMaximumStops`, public). They must all send the same cap,
  because the board cache scopes coverage on every query item except the window.
- **Gap rule:** a passlist counts as capped when it has exactly 10 entries and the last two aren't route
  neighbours (or either `routeIdx` is missing). The gap is the trip positions after the last aligned stop before
  the terminus and before the terminus (to the end of the trip if the terminus didn't align). Only there is the
  30-minute horizon dropped; the 2-hour bound stays. If the relay drops the parameter, passlists come back whole
  and the rule stays off.
- **Merge clamp:** `RealtimeTripPatch.merging` always applies `constrainingMinutePrecision` before its chronology
  check. That returns chronological patches unchanged.
- **Trip detail (added later that night, the owner's choice):** `RealtimeRoutingRequest.wholePasslists` (default
  `false`) drops the cap from every board fetch and cache lookup of that request. `TransitTripSnapshot` sets it, so
  stops more than eight after the boarding stop keep their live times. `routingBoardRequest` takes the flag with
  no default, so each of its five call sites reads it from the request. Routing requests are unchanged, so the
  replay below still applies.
- **Tests:** `CappedPasslistTests` (8) and `RealtimeTripPatchMergeClampTests` (2). With the gap rule, the clamp
  or trip detail's whole passlists turned off, the matching test fails. Seven existing test helpers that seed the
  cache with a hand-built routing request now send the cap. 364 of 364 pass serially with
  `ROUTING_VERIFY_KERNEL=1`.

Replayed offline on the current engine (Verkeier `eed8d9e`, no flags, [`tools/batch_real.sh`](tools/batch_real.sh)),
against the unchanged engine's original replays:

| Arm | Captures | Result-identical | Board bytes |
|---|---|---|---|
| `k10lastreal` | terminus kept, K = 10 | **4/4** | −51 % (`c28-esch`), −44 % (`s7-L1`) |
| `origreal` | whole passlists | **4/4** | unchanged |

No run dropped a patch as `invalidTripTimeline` (the unchanged engine dropped 6 in `c28-esch`). Predicted events
equal the experiment's gap arm, except two `s7-L1` samples with 18 fewer (2,312 against 2,330; not investigated).
With whole passlists every counter equals the original, so the unconditional clamp didn't act there. To find the
recorded boards, the scratch harness had to ignore `passlistMaxStops` in `BenchmarkRecordedTransport.key`. The
app's harness needs the same change before it can replay older captures with this engine.

**Two effects found while implementing** (both now handled):

- **The stop board no longer supplies routing.** `LiveTransitService` asks for `passlist=1` without a cap. With
  default filters, routing used to reuse that board from the cache; now the scopes differ, and
  `JourneyPlanningIntegrationTests.boardAndRouteEvidenceAgree`, which expects the reuse, will fail. The app reads
  only the terminus from those passlists (`isTerminalArrival`), and ATP keeps it, so the stop board now sends
  `passlistMaximumStops: HafasRealtimeRoutingProvider.routingPasslistMaximumStops`, and so does the test's
  hand-built stop board request. The test builds its own request, so it doesn't check `LiveTransitService`
  itself. The widget's board (`WidgetDepartureRefresher`) runs in its own process with its own cache and was
  left uncapped.
- **Trip detail would lose live times past the cap.** `TransitTripSnapshot` fetches through the routing
  acquisition, and it shows a live time only for reported events, so stops more than eight after the boarding stop
  would show only the timetable time. The owner chose whole passlists over showing the carried delay as an
  estimate, and trip detail now asks for them (see the trip detail bullet above). The cost: the cap is part of the
  cache scope, so trip detail can no longer reuse routing's boards, and it may send one or two more board requests
  per opening. The gap rule still looks for exactly 10 entries. A whole passlist of 10 that skips route indices at
  its end would turn it on, but the rule only adds estimated times, and trip detail shows none of them.

## Verdict

- **Implemented (night):** the real engine change kept every result, 4 of 4 samples with capped passlists and 4
  of 4 with whole ones, and the engine's 364 tests pass. Trip detail asks for whole passlists. The app pins
  `02e17cf` in `ef2c4c9`: the stop board sends the cap, the replay harness ignores `passlistMaxStops`, and the
  app's tests pass (326 with the uncommitted favourites work, 315 on the commit alone).
- **With the terminus kept, as ATP does it (evening replay):** K = 10 with the merge clamp and the gap rule kept
  every shown result, on 21 old-engine and 4 current-engine samples. The horizon change isn't needed any more.
  Unchanged code is not safe: buses lose their live data and line 651 lost its delay.
- **For production**, both changes should become real engine changes with unit tests: the gap rule should take K
  from the board request and pick the gap by position (after stop K − 2, before the terminus), not by "not in the
  passlist" as the experiment does, because that also catches stops ATP did list but that failed to align. It
  could also carry the delay in ATP's whole minutes (floor the timetable time, then add the minute delay). That is
  the form measured at 98.9 % above, and it would likely remove the `c28-rev` tie. That variant wasn't tested.
  The gap rule was only tested together with the merge clamp. *Done the same night, without the minute-aligned
  variant ([above](#the-engine-change-sunday-15-november-night)).*
- *The bullets below are from the first-K-stops replay and are kept for the record.*
- **K = 10 with both changes reproduced every result here:** 18 of 18 samples on the old engine, including four
  repeats of the case that failed before, and 4 of 4 on the current engine. It saves 43 % of decoded and about 46 %
  of wire bytes. Together with the CAND-12 (a) field trim, the saving is 85 % decoded and about 78 % wire.
- **K = 15 also reproduced everything** (−28 %). **K = 20 needs no engine change** (−15 %).
- **The changes need to become real engine changes with unit tests.** The horizon rule should take K from the
  board request, not the environment. The merge clamp only acts where the merge now throws away a whole patch, so
  it could apply without a cap too. Whether that fallback fires in today's live searches hasn't been measured.
- **Rides longer than K − 1 stops** lose their observed arrival unless another board reports their last stop
  (K = 5 above). Here that changed only labels, but a delay that changes along the ride would change times. A
  per-board K, from the stops between the board stop and the farthest target stop on the requested lines, is
  still the safer design for production.
- **Before any of this ships:** one live probe (two requests, with and without `passlistMaxStops`, through the
  app, with approval) to confirm that ATP caps from the board stop as assumed. *Done 15 November
  ([`probe/`](probe/README.md)): it does not. ATP keeps the board stop, the next K − 2 stops and the terminus.
  That shape was replayed the same evening (first bullet).* A broader replay on the current
  engine needs fresh captures, because the October ones no longer hold the boards it asks for. That also needs
  live ATP traffic.

## Files

- [`tools/trim_passlist.py`](tools/trim_passlist.py): caps passlists, optionally with the CAND-12 (a) field trim
  (imports [`tools/trim.py`](tools/trim.py), copied from `cand-12a-offline-2026-10-29`).
- [`tools/replay.sh`](tools/replay.sh), [`tools/batch.sh`](tools/batch.sh): replay one capture or every capture
  per arm (paths point to the session scratchpad and the dedicated simulator). `replay1.sh`/`batch1.sh` and
  `replay1b.sh`/`batch1b.sh` are the old engine with the horizon change, then with both changes;
  `replay2.sh`/`batch2.sh` and `replay2b.sh`/`batch2b.sh` are the same for the current engine. An arm named
  `k10fix` replays `captures-k10` with `ROUTING_PASSLIST_CAP=10`. [`BUILD.txt`](BUILD.txt) lists every build.
- [`tools/compare_arms.py`](tools/compare_arms.py): compares each arm with the original replay, and the original
  with the live capture (`--runs` picks the runs folder).
- [`tools/chronology_check.py`](tools/chronology_check.py): the horizon check above.
- [`engine-experiment.diff`](engine-experiment.diff): the two engine changes.
  [`engine-gap-rule.diff`](engine-gap-rule.diff): the gap rule, on top of them (identical file in both engines).
- Terminus-kept replay: `trim_passlist.py --keep-last`; [`tools/replay_c.sh`](tools/replay_c.sh) and
  [`tools/batch_c.sh`](tools/batch_c.sh) (`V=1` old engine, `V=2` current); [`tools/gap_estimate_check.py`](tools/gap_estimate_check.py)
  (the gap prognosis table); [`tools/bisect_tie.py`](tools/bisect_tie.py) (the `c28-rev` tie). Results:
  [`results/compare-a152c0f-terminus.json`](results/compare-a152c0f-terminus.json),
  [`results/compare-d98fb57-terminus.json`](results/compare-d98fb57-terminus.json),
  [`results/trim-stats-terminus.json`](results/trim-stats-terminus.json),
  [`results/gap-estimate-check.json`](results/gap-estimate-check.json); `brotli-totals.json` now also holds
  `k10last` and `f10last`.
- Engine change: [`engine-change.diff`](engine-change.diff) (the diff of `02e17cf` against `d98fb57`, including the
  new files); [`tools/batch_real.sh`](tools/batch_real.sh); results in
  [`results/compare-d98fb57-real-change.json`](results/compare-d98fb57-real-change.json).
  [`tools/compare_arms.py`](tools/compare_arms.py) now also accepts `real` arms.
- [`results/compare.json`](results/compare.json): every 14 November comparison.
  `results/compare-a152c0f-fix1.json`, `compare-a152c0f-fix1-clamp.json`, `compare-d98fb57-fix1.json` and
  `compare-d98fb57-fix1-clamp.json`: the 15 November comparisons (`fix1` = horizon change, `clamp` = both).
  [`results/trim-stats.json`](results/trim-stats.json): bytes and passlist counts per capture and arm.
  [`results/brotli-totals.json`](results/brotli-totals.json).
- The runs (about 1.2 GB) and capped captures stay in the session scratchpad, which can be cleared.
- [`probe/`](probe/README.md): the live probe (relay and app diffs, tools, dry-run and live results).
