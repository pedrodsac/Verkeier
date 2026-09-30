`esch-delayed-passlist.json` is a reduced, recorded ATP departure-board response
from 30 September 2026. It retains only the fields needed for matching and
prediction decoding. The bus 651 departure at Esch/Alzette, Gare routière was
planned at 18:09 and predicted at 18:38; its downstream passlist ends at
Volmerange-les-Mines. The matching official GTFS trip is `24284828`.

The fixture is used only by the opt-in `LiveRoutingBenchmark` test scheme. It
contains no credentials and makes no live requests. The test requires an
already-installed GTFS generation containing that service date and trip.
ATP/mobiliteit.lu is the source; see `docs/DATA_SOURCES.md` for usage and
attribution requirements.
