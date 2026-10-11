# iPhone 13: Gromscheed → Lorentzweiler timeout

On 11 October 2026, a physical iPhone 13 running an optimized Release build took **40.510 seconds** to finish this search. The production view model's 15-second deadline therefore expired before it could publish the transit results. Walking-transfer evaluation accounted for **34.444 seconds**.

The benchmark used the production service composition, downloaded walking graph, installed GTFS generation 5, and live ATP responses. Code coverage and the debugger were disabled. Its measurement-only 120-second deadline allowed the original search to finish; the production deadline remains 15 seconds.

The single live operation started at **10:53:10.735888 Europe/Luxembourg** (Unix timestamp `1791708790.735888`). Origin: Gromscheed, `49.6541071, 6.2296443`. Destination: Lorentzweiler, Gare, `49.698461, 6.140417`, GTFS stop `000160807006`. It acquired 30 responses covering 29 boards, 584 predicted events, and 3,932,513 response bytes.

Subsequent measurements replay these captured responses and bike availability with the same planning timestamp and coordinates, in fresh processes on the same phone. They make no additional live requests. Replay transport is faster than the live network, so the routing stages provide the most direct comparison of the code change.

## Timings

| Stage | Before: live | Previous replay | Latest replay |
| --- | ---: | ---: | ---: |
| Complete search through first render | 40.510 s | 12.950 s | 8.110 s |
| RAPTOR search, including walking transfers | 37.893 s | 11.548 s | 6.799 s |
| Walking transfers (subset of RAPTOR) | 34.444 s | 8.438 s | 5.241 s |
| Other RAPTOR work | 3.449 s | 3.110 s | 1.558 s |
| Realtime acquisition and processing | 1.466 s | 0.197 s | 0.230 s |
| Snapshot preparation | 0.527 s | 0.547 s | 0.515 s |
| Endpoint discovery | 0.165 s | 0.214 s | 0.152 s |
| Walking graph preparation | 0.143 s | 0.195 s | 0.149 s |
| Map render after publication | 0.172 s | 0.116 s | 0.127 s |

Stages can overlap; the walking row is included in RAPTOR. Live HTTP/decode counters accumulate concurrent work and must not be summed as wall-clock latency. Both after measurements use local recorded transport, not additional live searches. With the original live realtime duration substituted, the latest approximate total would be 9.35 seconds; that is an estimate, not an additional measurement. Network variation can still affect the production deadline.

Walking requests fell from 26,986 to 8,856, and cache misses from 15,899 to 3,516. The initial search pass fell from 18.293 to 5.934 seconds; the realtime pass fell from 19.601 to 0.865 seconds. Peak process memory was 401.9 MB in the live baseline, 464.4 MB in the previous replay, and 410.3 MB in the latest replay; these fresh-process high-water marks include the map, graph and routing profiles, not just the walking cache. The latest replay is 37% faster than the previous replay; RAPTOR itself uses 82% less time than the live baseline.

Both displayed itineraries match exactly, including legs, times and IDs: 850 → 111 arriving at 12:01:34, and 850 → RB arriving at 12:38. All six exported candidate routes match. Internal retained-alternative counters differ (25 versus 24); those counters are not a comparison of every retained itinerary.

## Changes

- Compute a conservative latest boarding deadline for each walking-transfer target, respecting service dates, allowed modes, pickup restrictions, cancellations, and reported/estimated realtime. Skip targets with no catchable vehicle; retain final walking egress even without a future departure.
- After measuring a walk, discard labels that miss every eligible departure. These labels cannot board in the next round.
- Replace sorting the entire walking cache on each eviction with bounded, amortized constant-time LRU maintenance.
- Increase the shared walking cache from 4,096 to 8,192 entries so a dense search can reuse paths during its realtime recalculation.
- Bound executable destination reachability to the walking batches the router actually performs: one pedestrian batch after station pathways in each round. Unlimited walking chains had made almost the entire country appear reachable without another vehicle ride.
- Restrict each round's walking targets to pickups before a useful alighting position in the next round. A vehicle must be able to finish within the remaining rides. Keep the realtime discovery envelope optimistic so board acquisition retains its prior behavior.
- Resolve relative benchmark capture folders in the app's temporary directory, allowing replay after iOS relocates the app data container during installation.

The optimizations impose no arbitrary transfer-pair quota and preserve precise walking/funicular durations. Package revisions: baseline `4bfe3e9`, initial pruning/LRU `cdf54c4`, measured-arrival pruning `641085d`, cache capacity `73cd8f6`, executable transfer bounds `8196815`, and preserved realtime discovery `ac6945e`. The previous replay used `73cd8f6`; the latest used `ac6945e`.

The intermediate same-phone replay, before measured-arrival pruning and the cache increase, took **17.340 seconds**: a large improvement, but still above the production deadline. Its displayed journeys and all six exported candidate routes exactly matched the live baseline.

## Verification

The final package passed 256 offline Swift Testing tests with `ROUTING_VERIFY_KERNEL=1`, including independent routing-oracle tests, the previously lost midnight interchange beyond 96 earlier pairs, reported versus estimated delays, cancellations, inactive service days, final walking egress, directed pathways before walking, and active distractor interchanges that need too many remaining rides. The app's full Release simulator suite passed 210 tests. An additional installed-feed overnight replay retained the RB arrival at Lorentzweiler at 01:25.

`baseline-live.json`, `intermediate-replay.json`, `final-replay.json` (previous cache improvement), and `bounded-replay.json` (latest executable bounds) contain timing and exported route records. The latest strict replay acquired all 30 captured responses, covered 29 boards, and had no incomplete boards. An earlier diagnostic exposed a changed discovery query; that incomplete run is excluded from the measurements above. `capture-manifest.json` identifies the 30 recorded response bodies by SHA-256; raw responses remain outside the repository.
