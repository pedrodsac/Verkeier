# Validation provenance

- Package `5649aeb2f611968821699d8c18da6a521d8f37c3`: `ROUTING_VERIFY_KERNEL=1 swift test`; 96 tests in nine suites passed. Source log: `/tmp/MobiliteitKitPeerLookupTests.log`.
- App `53858b6`, pinned package above: Release simulator `xcodebuild test -enableCodeCoverage NO`; 41 tests in nine suites passed. Source log: `/tmp/VerkeierPeerLookupFinalTests.log`.
- Installed full-feed differential comparison passed after scalar alighting and direct profile materialization (`367bc06`). Source log: `/tmp/MobiliteitKitFinalScalarVerification.log`, `InstalledTimetableBenchmarkTests.installedTimetable`. That full-feed invocation also enabled older benchmarks concurrently, exhausting several realtime fixture deadlines; the complete ordinary suite was rerun independently and passed. Timing data from that overloaded invocation is not used.
- Release primary matrix: 300 timed samples plus ten discarded priming samples; all 310 unique request identifiers, nonempty options and positive first-render timings validated. Every recorded-live operation matched predictions. No route timeout or shorter horizon counted as success.
- Debug audit: four timed samples plus two discarded priming samples, built with coverage off; all rendered, separately reported without a five-second acceptance claim.
- `visible-route-sheet.png`: production RouteView in the Release simulator harness after a final 2,895 ms arrive-by calculation. Five alternatives are present and loading is finished. The fixed historical scenario displays the existing missed-journey state against the current clock.

`metadata.json` identifies revisions, hardware and method. `summary.json` and `samples.jsonl` are the final pinned Release matrix; `debug-*` contains the separate audit. The earlier actual-network measurements and successful live “now” spot samples are clearly separated in `live-*` files.
