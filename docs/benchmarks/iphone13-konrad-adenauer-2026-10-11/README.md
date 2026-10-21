# iPhone 13: Gromscheed → Kirchberg, Konrad Adenauer

One live departure search ran at **11:47:12.890348 Europe/Luxembourg on 11 October 2026** (Unix timestamp `1791712032.890348`). A fresh process on the physical iPhone 13 used an optimized Release build, the production view model, service composition, walking graph, installed GTFS generation 5, live ATP responses and live bike availability. Code coverage and the debugger were disabled. MobiliteitKit revision: `ac6945e96e84cc3614317024cae716b0f90aca5c`; app routing revision: `fb33723`, with the existing uncommitted UI changes included in the build.

Origin: Gromscheed, `49.6541071, 6.2296443`. Destination: the timetable stop **Kirchberg, Konrad Adenauer**, `49.62995, 6.158028`, GTFS ID `000200417019`. These are the stop's actual feed coordinates; the benchmark harness's older default coordinate is not used.

## Timings

| Stage | Wall-clock time |
| --- | ---: |
| Complete search through first render | **9.941 s** |
| RAPTOR, including walking transfers | 7.493 s |
| Walking transfers (included in RAPTOR) | 4.908 s |
| Other RAPTOR work | 2.585 s |
| Initial search pass | 6.033 s |
| Realtime search pass | 1.460 s |
| Realtime acquisition and processing | 1.266 s |
| Snapshot preparation | 0.473 s |
| Walking graph preparation | 0.145 s |
| Endpoint discovery | 0.143 s |
| Candidate building | 0.332 s |
| Bike calculation (concurrent) | 0.560 s |
| Map rendering after publication | 0.067 s |

Walking is a subset of RAPTOR; the two search-pass rows also sum to RAPTOR. Bike calculation overlaps routing preparation and realtime acquisition. HTTP counters accumulate concurrent work and are not elapsed latency. `live.json` contains the individual operation-relative spans.

This single sample finished about 5.06 seconds before the production 15-second timeout. The measurement harness uses a 120-second ceiling so an overrun can be measured; the production deadline remains unchanged. This is a live measurement, not a recorded-response replay or an average across runs.

## Results and work

The search fetched **29 ATP responses covering 29 boards**, with **0 incomplete boards**, 1,651 predicted events and 6,643,468 response bytes. It made 13,600 walking requests: 9,877 cache hits and 3,723 path calculations. Peak process memory was **455.6 MB** (decimal). It generated 3,600 internal route candidates, exported six candidate journeys, and displayed four journeys.

| Displayed journey | Leave Gromscheed | Arrive Konrad Adenauer | Realtime coverage |
| --- | --- | --- | --- |
| Walk → 29 → 6 | 11:58:40 | **12:24** | Live |
| Walk → 321 → walk → T1 → walk → 16 | 12:07:45 | 12:40 | Partial |
| Walk → 223 → 6 | 12:28:45 | 12:54 | Live |
| Walk → 29 → 16 | 13:05:40 | 13:40 | Live |

The first journey walks to Senningerberg, Charlys Statioun and changes from 29 to 6 at Senningerberg, Héienhaff. Raw response bodies and the recorded bike snapshot remain outside the repository for offline follow-up. `capture-manifest.json` identifies this run's response bodies by SHA-256. No further live route searches were performed for this benchmark.
