#!/bin/zsh
# Step 7 live re-baseline of docs/ROUTING_SPEED_PLAN.md.
# Owner approval (2026-10-19): simulator, Tuesday 2026-10-20 around 17:45, 3 rounds of
# priming, warm and cold, about 245 ATP requests, transfer-walk build as the CPU canary.
#
# Live rounds run back to back inside the approved window. Then each round's capture is
# replayed with recorded latency (request budget 0, no ATP). Writes only below this
# script's directory. Exit codes: 0 done, 2 refused or stopped by a guard, 3 a live run failed.
set -u
HERE=${0:A:h}
APP="$HERE/app/Verkeier.app"
REPO=/Users/pedoataidecordeiro/Developer/Verkeier
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
BUNDLE=dev.pedrocordeiro.Verkeier
cd "$REPO" || exit 2

in_window() {
  [[ $(date +%Y-%m-%d) == 2026-10-20 ]] || return 1
  local t=$(date +%H%M)
  (( 10#$t >= 1730 && 10#$t <= 1915 ))
}
heavy() { pgrep -f 'xcodebuild|swift-test|swift-build|benchmark_routes' >/dev/null; }
power() { echo "power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/") lowpower=$(pmset -g | awk '/lowpowermode/ {print $2}')"; }
requests() { python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$1/transport.json" 2>/dev/null || echo 0; }

[[ -d "$APP" ]] || { echo "REFUSED: no app at $APP"; exit 2; }
in_window || { echo "REFUSED: $(date '+%F %T') is outside the approved window (2026-10-20 17:30-19:15)"; exit 2; }
container=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data 2>/dev/null)
ls "$container/Library/Application Support/Mobiliteit/"gtfs-generation-*.sqlite >/dev/null 2>&1 \
  || { echo "REFUSED: no installed timetable in the simulator's app container"; exit 2; }
pmset -g batt | head -1 | grep -q "AC Power" || { echo "REFUSED: not on mains power ($(power))"; exit 2; }
[[ $(pmset -g | awk '/lowpowermode/ {print $2}') == 1 ]] && { echo "REFUSED: Low Power Mode is on"; exit 2; }

echo "=== start $(date '+%F %T') $(power) app=$APP"
total=0
for i in 1 2 3; do
  # A finished round is never repeated or overwritten.
  [[ -e "$HERE/L$i" ]] && { n=$(requests "$HERE/L$i"); total=$((total + n)); echo "skip: live round $i already ran ($n requests)"; continue; }
  while heavy; do
    in_window || { echo "STOP: another heavy job kept running until the window closed (total $total)"; exit 2; }
    echo "waiting: another heavy job is running $(date +%T)"; sleep 30
  done
  in_window || { echo "STOP: window closed before live round $i (total $total)"; exit 2; }
  echo "=== round $i live $(date +%T) $(power)"
  python3 Scripts/benchmark_routes.py --app "$APP" --device "$DEVICE" --output "$HERE/L$i" --scenarios live-now \
    --warm 1 --cold 1 --maximum-limit-ms 0 --request-budget 100 > "$HERE/L$i.log" 2>&1
  live_status=$?
  n=$(requests "$HERE/L$i")
  total=$((total + n))
  echo "live round $i exit $live_status, requests $n, total $total"
  if (( live_status != 0 )); then echo "live round $i failed; no further live rounds"; tail -5 "$HERE/L$i.log"; break; fi
  (( n > 90 )) && { echo "STOP: round $i used more than 90 requests"; break; }
done

for i in 1 2 3; do
  [[ -f "$HERE/L$i/samples.json" && -d "$HERE/L$i/network" ]] || continue
  epoch=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(repr([s for s in d if s["process"]=="priming"][0]["planningTime"]))' "$HERE/L$i/samples.json")
  while heavy; do echo "waiting before replay $i: another heavy job is running $(date +%T)"; sleep 30; done
  echo "=== round $i replay $(date +%T) epoch $epoch"
  python3 Scripts/benchmark_routes.py --app "$APP" --device "$DEVICE" --output "$HERE/R$i" --scenarios live-now \
    --warm 1 --cold 1 --maximum-limit-ms 0 --request-budget 0 \
    --capture-directory "$HERE/L$i/network" --bike-fixture "$HERE/L$i/bike-snapshot.json" \
    --epoch "$epoch" --replay-latency > "$HERE/R$i.log" 2>&1
  echo "replay $i exit $?"
done
echo "=== done $(date '+%F %T'), ATP requests $total"
(( ${live_status:-0} == 0 )) || exit 3
