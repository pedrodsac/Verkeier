# `passlistMaxStops` live probe (15 November 2026)

The offline replay ([`../README.md`](../README.md)) assumed that `passlistMaxStops=K` keeps the board stop and
the next K − 1 stops. This probe checks what ATP really returns. The app sends two `departureBoard` requests
for one stop and window from the iOS Simulator, one without and one with the cap, and saves both bodies. A
script then compares them passlist by passlist.

**Result: ATP keeps the terminus.** With `passlistMaxStops=10`, every passlist longer than 10 stops came back
as the board stop, the next 8 stops and the last stop: exactly 10 stops. Each one is byte-identical to the
uncapped list, realtime fields included. The offline replay tested a different shape (the first 10 stops), so
its 18/18 result does not carry over yet. This comes from one live run of 2 requests, on Sunday 15 November at
18:13.

## Live result (Sunday 15 November, 18:13)

- **Relay:** the change was deployed first (version `f4e020d1`, tag `passlist-v3`). Both responses carry
  `X-Verkeier-Relay-Version: passlist-v3`, so the new relay served them.
- **App:** the dry-run build with `--base-url` set to the production relay URL, so only the probe's two
  requests could reach the relay. It ran on the dedicated simulator, which was shut down afterwards.
- **Request:** stop `000220402034` (Esch-sur-Alzette, Gare routière), 18:13, 30 minutes, cap 10. On a Sunday
  evening that window held only 4 departures, all with passlists longer than 10 stops.

| Line | Departure | Full passlist (`routeIdx`) | Capped `routeIdx` | Terminus in the capped list |
|---|---|---|---|---|
| 650 | 18:14 (+2) → Bettembourg, Gare routière | 30 stops (10–39) | 10–18, 39 | 18:49, prognosed 18:51 |
| 13 | 18:22 → Rodange, Rue Joseph Moscardo | 47 (0–46) | 0–8, 46 | 19:18, prognosed 19:18 |
| 651 | 18:24 (+1) → Volmerange-les-Mines, Gare routière | 21 (20–40) | 20–28, 40 | 18:47, prognosed 18:48 |
| 3 | 18:33 → Rodange, Schwemm | 56 (0–55) | 0–8, 55 | 19:37, scheduled only |

What this settles:

- **Shape:** `prefix+last`. K counts the board stop and the terminus, as the WADL says, and the capped list is
  exactly K long.
- **Kept stops are unchanged:** every field matches the uncapped list, realtime and prognosis included. The
  departures themselves are identical. Nothing marks a list as cut; the gap shows only as a jump in `routeIdx`.
- **Start:** the passlist starts at the board stop, also for trips that began earlier (`routeIdx` 10 and 20).
- **Bytes:**
  - the decoded body went from 167 KB to 52 KB (−69 %);
  - passlists are 95 % of this board;
  - both responses were brotli-compressed on the wire;
  - the relay's upstream wait was 120 ms, then 64 ms. That is one pair of requests, not a measurement.

**Not covered:** this is 4 departures in one window. The shape is a server rule, and it held in all 4 and
matches the WADL. Untested: values of K other than 10, passlists of exactly K or K + 1 stops, and cancelled
stops inside the gap.

**What it means for the engine:**

- A ride that ends at the terminus keeps its reported arrival.
- A ride that ends inside the gap gets no report for its alighting stop, as with a prefix.
- The horizon change was written for a prefix, where nothing is reported after stop K. Here a reported stop
  follows the gap. Whether the unchanged engine still lets the estimate go back in time, and whether the
  change is still needed (or still right), needs an offline replay with the terminus kept.

## Why the shape mattered

ATP's WADL (`https://cdt.hafas.de/opendata/apiserver/departureBoard?wadl`) describes the parameter as
"Maximum number of stops including requested stop and last stop. Minimum of 0." Read literally, ATP keeps the
terminus, and the live run confirmed that. That is **not** the shape the offline replay tested. A capped passlist would then hold the first
K − 1 stops plus the last stop, with a gap of unreported stops between them.

Of the two engine changes behind the 18/18 result, the horizon change assumes a prefix: when a passlist has K
stops, it keeps the last reported delay to the trip's end. With a terminus kept, the engine would instead see
a reported time at the end of the gap. The horizon change would need to treat the gap differently, and the
offline replay would need a `prefix+last` trim before K = 10 could be trusted. The merge clamp does not depend
on the shape.

## What it changes

No code in the app or engine repositories was changed; this folder is the only addition there. The relay
change is deployed but not committed.

- **Relay** ([`relay-passlistMaxStops.diff`](relay-passlistMaxStops.diff)):
  - `departureBoard` forwards `passlistMaxStops`, validated as an integer from 0 to 1,000 (ATP's documented
    minimum is 0);
  - it is forwarded only when the caller sends it;
  - two tests cover rejection of `-1`, `2.5`, `1001` and `ten`, and pass-through of `10` and `0`;
  - `X-Verkeier-Relay-Version` goes to `passlist-v3`. No client reads it; it shows which relay answered;
  - `npm run typecheck` is clean and `node --test` passes 8/8.

  Before this change the relay dropped the parameter (its allowlist had no `passlistMaxStops`), so a "capped"
  request silently came back uncapped.

  **Deployed** on 15 November at 18:12 as version `f4e020d1-8f18-4451-84a0-ef1fd1cf66c9` (tag `passlist-v3`),
  from branch `probe/passlist-max-stops` in `verkeier-relay`. It is **not committed**. The previous version,
  `8f513969-7425-4b4a-afbb-db559ee276b9` (deployed 20 October, 12 minutes after `main` `f9c9f75`), is the
  rollback target:

  ```sh
  npx wrangler rollback 8f513969-7425-4b4a-afbb-db559ee276b9
  ```
- **App** ([`app-passlist-probe.diff`](app-passlist-probe.diff), on Verkeier `eed8d9e`): a `passlist-probe`
  scenario in the simulator benchmark harness (`PasslistProbe.swift`, simulator and benchmark builds only). It
  sends the two requests through the app's relay and saves the raw bodies and timings to the app's `tmp`. It
  does no routing. An optional `ROUTING_PASSLIST_PROBE_BASE_URL` points it at a local server instead. A
  malformed override aborts rather than falling back to the relay.
- **Tools** ([`tools/`](tools)):
  - `mock_relay.py`: a local stand-in for the relay. It serves one recorded board and cuts passlists to a
    chosen shape when the request carries the cap: `prefix`, `prefix-last`, `thin` or `ignore`.
  - `passlist_probe.py`: `run` installs and launches the probe in a simulator and copies the bodies out;
    `analyze` compares them.
  - `selftest_classifier.py`: checks `analyze` offline against every mock shape.

## The two requests

Both requests use the same query:

| Parameter | Value |
|---|---|
| `format` | `json` |
| `id` | the stop |
| `lang` | `en` |
| `date`, `time` | pinned once at launch (Europe/Luxembourg) |
| `duration` | 30 |
| `maxJourneys` | −1 |
| `rtMode` | `SERVER_DEFAULT` |
| `passlist` | 1 |

The second request adds `passlistMaxStops=K`. They run one after the other on an ephemeral `URLSession` with
the cache bypassed. Unlike the engine's boards, they send no `lines` filter, so every departure in the window
is compared.

**Stop used:** `000220402034` (Esch-sur-Alzette, Gare routière), K = 10, 30 minutes. In the 19 October
`c28-esch` capture, 48 of the 54 departures on its line-filtered two-hour board had passlists longer than
10 stops, up to 57. That is 2 requests against the shared key's documented
500 per hour.

## What the analysis reports

Departures are matched by `JourneyDetailRef`, date, time and board platform; stops by `extId` and `routeIdx`.
For every matched passlist the shape is one of:

| Shape | Meaning |
|---|---|
| `unchanged-short` | the full passlist already has K stops or fewer |
| `unchanged-long(cap ignored)` | longer than K and still complete: the cap did not arrive or was ignored |
| `prefix` | the first stops only (the offline assumption) |
| `prefix+last` | the first stops and the terminus (the WADL reading) |
| `subsequence[+first][+last]` | a thinned list |
| `other` | anything else |

The analysis also reports:

- capped length minus K, which shows how ATP counts;
- whether the capped list starts at the board stop;
- departures present in only one response;
- field differences on shared stops, with realtime fields listed separately: the two requests are a fraction
  of a second apart, so a few realtime changes are possible;
- bytes;
- a one-line verdict.

## Dry run (15 November)

**Build** ([`BUILD.txt`](BUILD.txt)):

- Verkeier `eed8d9e` with the probe diff and MobilitéitKit `d98fb57`;
- Release simulator build, `ENABLE_CODE_COVERAGE=NO`;
- `API_PROXY_URL=` emptied, so the build holds no relay address. Checked: the Info.plist value is empty and the
  relay host appears nowhere in the bundle.

It ran on the dedicated iOS 27.2 iPhone 17 simulator, which was shut down afterwards.

**Mock:** `mock_relay.py` on 127.0.0.1 served one recorded board from the 19 October `c28-rev` capture:

- Kirchberg, Gare routière Luxexpo, 18:20–21:00;
- 155 departures, 3.1 MB;
- 99 passlists longer than 10 stops.

| Run | Mock behaviour | Requests the mock received from the app | Outcome |
|---|---|---|---|
| 1 | `prefix-last` | 2, identical but for `passlistMaxStops=10` on the second | `prefix+last` in all 99 passlists longer than the cap, each exactly K long; body −49 % |
| 2 | `ignore` | 2, as above | "ATP ignored passlistMaxStops" |
| 3 | cap −1 | none | abort `passlist-probe-missing-stop-or-cap` |
| 4 | base URL `not a url` | none | abort `passlist-probe-bad-base-url` |

Summaries and request checks are in [`results/dry-run/`](results/dry-run).

**Runner guards** (all checked). A dry run is refused when:

- the app was built with a relay;
- `--base-url` is missing;
- the base URL does not answer the mock's marker path.

An abort is reported as an abort even though the scenario prints `DONE` after it.

**Plain HTTP:** the simulator reached plain-HTTP 127.0.0.1 without an ATS exception, so a local `wrangler dev`
relay works the same way.

**Timings:** the first request took 943 ms (cold app and connection), the second 91 ms. Timings in the live run
will not measure what the cap saves.

**Classifier self-test.** [`tools/selftest_classifier.py`](tools/selftest_classifier.py) ran on the same board,
once per mock shape and once on the offline K = 10 trim (output in
[`results/dry-run/selftest-classifier.txt`](results/dry-run/selftest-classifier.txt)):

| Capped body | Shapes of the 99 long passlists | Capped length − K | Verdict |
|---|---|---|---|
| mock `prefix` | 99 `prefix` | 0 | prefix |
| mock `prefix-last` | 99 `prefix+last` | 0 | prefix+last |
| mock `thin` | 99 `subsequence+first+last` | 0 | thinned |
| mock `ignore` | 99 `unchanged-long(cap ignored)` | 2 to 32 | cap ignored |
| offline `trim_passlist.py` K = 10 | 99 `prefix` | 0 | prefix |
| `prefix-last` + one changed `rtDepTime` + one dropped departure | 98 `prefix+last` | 0 | prefix+last, with 1 realtime mismatch and 1 departure only in the full body |

With K ≤ 2, a thinned list and `prefix+last` look the same, so use K ≥ 5.

## Running it again (needs approval)

Every run sends two ATP requests. Pick one way to route them, then run the probe with `--live`.

**A. Local relay (no deploy).** Apply the diff on a branch of `verkeier-relay` (`git apply`; it applies cleanly
to `f9c9f75`) and run `wrangler dev` there. The relay then runs on the Mac and reads the existing `.dev.vars`
where it is, so the secret is neither copied nor printed. Point the dry-run build at it:

```sh
git switch -c probe/passlist-max-stops && git apply <this folder>/relay-passlistMaxStops.diff
```

```sh
npm ci && npm test && npx wrangler dev --port 8787
```

```sh
python3 -I tools/passlist_probe.py run --live --base-url http://127.0.0.1:8787 \
  --app <dd-dry>/Build/Products/Release-iphonesimulator/Verkeier.app --device <simulator udid> \
  --stop 000220402034 --cap 10 --out results/live-<date>
```

**B. Deployed relay** (used on 15 November). Apply the diff in `verkeier-relay` and run `npm run typecheck`,
`npm test` and `npx wrangler deploy --keep-vars`. Then run the same command with
`--base-url https://verkeier-api.pedrocordeiroo2.workers.dev`. Building the probe app without the
`API_PROXY_URL=` override and dropping `--base-url` does the same. The extra parameter is harmless for the
shipped app, which never sends it.

Either way, never on a physical device. The output folder gets:

- `full.json`, `capped.json` and their `.meta.json` files (URL, status, bytes, time, response headers);
- `console.log`;
- `summary.json`.

## Next step

The live shape is `prefix+last`, so:

1. ~~Add a keep-terminus option to `trim_passlist.py`.~~ Done (`--keep-last`).
2. ~~Replay K = 10 offline with the terminus kept.~~ Done the same evening
   ([parent README](../README.md#terminus-kept-sunday-15-november-evening)). K = 10 needs the merge clamp and a
   gap rule (stops left out keep the last reported delay, with no 30-minute horizon). With both, every shown result
   was identical on 21 old-engine and 4 current-engine samples.
3. Decide whether the relay change is committed or rolled back. It is harmless while nothing sends the
   parameter, and the app needs it once the engine changes land.

Live files: [`results/live-2026-11-15/`](results/live-2026-11-15) holds the summary, both requests' metadata
(URL, status, bytes, headers) and `passlists.json`, an extract of every passlist. The full bodies stay in the
session scratchpad.
