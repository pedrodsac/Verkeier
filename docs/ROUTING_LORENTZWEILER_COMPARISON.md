# Gromscheed 18A → Lorentzweiler, Gare

Browser comparison against the [Mobiliteit journey planner](https://www.mobiliteit.lu/en/plan-a-trip/), queried on 10 October 2026 with departure fixed at **23:33 Europe/Luxembourg**. The website resolves the origin to Senningerberg, Gromscheed 18A; the app uses its existing regression coordinate `49.6541071, 6.2296443`. Destination: GTFS `000160807006`, coordinate `49.698461, 6.140417`.

## Official results observed in the browser

| Connection | Key times | Arrival on 11 October |
|---|---|---|
| 850 → T1 → LNB LWS | 850 at Charlys Statioun 23:44 (+3); T1 Héienhaff P+R 00:08–00:24; LNB LWS Pfaffenthal Halte CFL 00:31–01:05; final 2-minute walk | **01:07** |
| 212 → T1 → LNB LWS | 212 at Charlys Statioun 00:02 (+1); website warns a connecting service may not be reachable | 01:07, warning |
| 325 → T1 → RB 3701 | Walk 1.4 km to Laangschib; 325 00:22–00:26 to Hugo Gernsback; walk to Luxexpo; T1 00:42–00:51; walk to Pfaffenthal-Kirchberg Gare; RB 01:14–01:25 | **01:25** |
| 212 → T1 → RB 3701 | 212 at Charlys Statioun 00:02 (+1) | **01:25** |
| 29 → RB 3605 | 29 at Charlys Statioun 05:12 | 06:08 |

The latest archive discovered from the official dataset API is the 7 October–12 December feed, published 8 October. Installed generation 5 contains the 01:14 RB train (trip `24455256`, active service date 11 October), but no LNB LWS route or its calls at Pfaffenthal Halte CFL. Matching the 01:07 arrival requires a supported source for that missing service. The router must not invent a night-bus timetable or label scheduled data as live.

## Router correction

Walking-transfer relaxation previously stopped after **96 distinct stop pairs per boarding round**. Pairs were ordered by earliest arrival at the source. On dense profiles, earlier interchanges exhausted the quota before the tram-to-rail walk at Pafendall was considered. The router consequently found no overnight journey and expanded the search to morning.

MobiliteitKit `7d7d9ba` removes this global truncation. Conservative destination reachability filters impossible targets, while the pedestrian provider retains bounded concurrency, routed-evidence requirements and the existing 15-minute/1.5-km transfer limits. Every retained arrival label still receives its verified walking transfer.

The deterministic installed-feed replay now recovers 850/T1/RB, 212/T1/RB and 325/T1/RB arriving **01:25**, matching Mobiliteit's rail alternatives. Its synthetic walking provider isolates the search bug; it does not establish real pedestrian feasibility. The separate rendered simulator comparison uses the installed pedestrian graph.

## Verification

- A new offline fixture puts the sole usable midnight interchange after 110 earlier pairs. It verifies the final connection and next-day arrival.
- The installed-feed replay verifies the exact RB trip and 01:25 arrival, including a coordinate origin. Both tests pass with reference-kernel verification enabled.
- The ordinary package suite passes **239 tests in 36 suites**, with reference-kernel verification and no live networking.

## Reproduce the app comparison

Build Release with coverage disabled, using the installed datasets. The benchmark now accepts an explicit destination:

```sh
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-lorentzweiler-comparison \
  --scenarios depart --time 2026-10-10T23:33:00+02:00 \
  --destination-name 'Lorentzweiler, Gare' \
  --destination-coordinate 49.698461 6.140417 \
  --destination-stop 000160807006 --warm 0 --cold 0 \
  --maximum-limit-ms 20000
```

`depart` uses empty fixture ATP boards for a reproducible timetable comparison. `live-now` uses the configured production proxy; combining it with the fixed timestamp checks live evidence for the same planning anchor. A single operation is a spot check, not a latency distribution.

## Funicular follow-up

The Pafendall connection is now explicitly included. The installed graph measures
370.5 m / 4 min 11 s in either direction, including a 63-second ride and a
60-second boarding allowance. The overnight route uses **325 → T1 → Funicular →
RB**, boarding at Pfaffenthal-Kirchberg at 01:14 and arriving at Lorentzweiler at
01:25. See [Pafendall funicular](PAFENDALL_FUNICULAR.md) for implementation,
measurement conditions, and regression coverage.
