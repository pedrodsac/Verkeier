# iPhone 13: Gromscheed → Lorentzweiler timeout

On 11 October 2026, a physical iPhone 13 running an optimized Release build took **40.510 seconds** to finish this search. The production view model's 15-second deadline therefore expired before it could publish the transit results. Walking-transfer evaluation accounted for **34.444 seconds**.

The benchmark used the production service composition, downloaded walking graph, installed GTFS generation 5, and live ATP responses. Code coverage and the debugger were disabled. Its measurement-only 120-second deadline allowed the original search to finish; the production deadline remains 15 seconds.

The single live operation started at **10:53:10.735888 Europe/Luxembourg** (Unix timestamp `1791708790.735888`). Origin: Gromscheed, `49.6541071, 6.2296443`. Destination: Lorentzweiler, Gare, `49.698461, 6.140417`, GTFS stop `000160807006`. It acquired 30 responses covering 29 boards, 584 predicted events, and 3,932,513 response bytes.

Subsequent measurements replay these captured responses and bike availability with the same planning timestamp and coordinates, in fresh processes on the same phone. They make no additional live requests. Replay transport is faster than the live network, so the routing stages provide the most direct comparison of the code change.

## Timings

| Stage | Before: live | After: recorded replay |
| --- | ---: | ---: |
| Complete search through first render | 40.510 s | 12.950 s |
| RAPTOR search, including walking transfers | 37.893 s | 11.548 s |
| Walking transfers (subset of RAPTOR) | 34.444 s | 8.438 s |
| Other RAPTOR work | 3.449 s | 3.110 s |
| Realtime acquisition and processing | 1.466 s | 0.197 s |
| Snapshot preparation | 0.527 s | 0.547 s |
| Endpoint discovery | 0.165 s | 0.214 s |
| Walking graph preparation | 0.143 s | 0.195 s |
| Map render after publication | 0.172 s | 0.116 s |

Stages can overlap; the walking row is included in RAPTOR. Live HTTP/decode counters accumulate concurrent work and must not be summed as wall-clock latency. The after measurement uses local recorded transport, not a second live search. With the original live realtime duration substituted, its approximate total would be 14.22 seconds; that is an estimate, not an additional measurement. Network variation can still exhaust the remaining deadline margin.

Walking requests fell from 26,986 to 21,264. Cache misses fell from 15,899 to 6,036. The realtime search pass fell from 19.601 to 1.866 seconds. Peak process memory was 401.9 MB before and 464.4 MB after; these fresh-process high-water marks include the map, graph and routing profiles, not just the walking cache.

Both displayed itineraries match exactly, including legs, times and IDs: 850 → 111 arriving at 12:01:34, and 850 → RB arriving at 12:38. All six exported candidate routes match. Internal retained-alternative counters differ (25 versus 24); those counters are not a comparison of every retained itinerary.

## Changes

- Compute a conservative latest boarding deadline for each walking-transfer target, respecting service dates, allowed modes, pickup restrictions, cancellations, and reported/estimated realtime. Skip targets with no catchable vehicle; retain final walking egress even without a future departure.
- After measuring a walk, discard labels that miss every eligible departure. These labels cannot board in the next round.
- Replace sorting the entire walking cache on each eviction with bounded, amortized constant-time LRU maintenance.
- Increase the shared walking cache from 4,096 to 8,192 entries so a dense search can reuse paths during its realtime recalculation.
- Resolve relative benchmark capture folders in the app's temporary directory, allowing replay after iOS relocates the app data container during installation.

The optimizations impose no arbitrary transfer-pair quota and preserve precise walking/funicular durations. Package revisions: baseline `4bfe3e9`, initial pruning/LRU `cdf54c4`, measured-arrival pruning `641085d`, final cache capacity `73cd8f6`.

The intermediate same-phone replay, before measured-arrival pruning and the cache increase, took **17.340 seconds**: a large improvement, but still above the production deadline. Its displayed journeys and all six exported candidate routes exactly matched the live baseline.

## Verification

The final package passed 254 offline Swift Testing tests with `ROUTING_VERIFY_KERNEL=1`, including independent routing-oracle tests, the previously lost midnight interchange beyond 96 earlier pairs, reported versus estimated delays, cancellations, inactive service days, and final walking egress. The app's full Release simulator suite passed 205 tests. An additional installed-feed overnight replay retained the RB arrival at Lorentzweiler at 01:25.

`baseline-live.json`, `intermediate-replay.json`, and `final-replay.json` contain timing and exported route records. `capture-manifest.json` identifies the 30 recorded response bodies by SHA-256; raw responses remain outside the repository.
