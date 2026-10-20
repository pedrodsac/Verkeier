#!/bin/zsh
# One live `live-now` round (priming, warm, cold; about 81 ATP requests) with the relay's
# Server-Timing header, approved by the owner on 2026-10-20. It waits up to 30 minutes for
# mains power, Low Power Mode off and a quiet machine; otherwise it gives up without a request.
# ALLOW_BATTERY=1 (owner, 2026-10-20) skips the mains-power check.
# Writes only below this script's directory. Exit: 0 done, 2 gave up, 3 the run failed.
set -u
HERE=${0:A:h}
APP="$HERE/app/Verkeier.app"
REPO=/Users/pedoataidecordeiro/Developer/Verkeier
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
cd "$REPO" || exit 2
[[ -d "$APP" && ! -e "$HERE/L1" ]] || { echo "REFUSED: no app, or L1 already exists"; exit 2; }

ready() {
  [[ ${ALLOW_BATTERY:-0} == 1 ]] || pmset -g batt | head -1 | grep -q "AC Power" || return 1
  [[ $(pmset -g | awk '/lowpowermode/ {print $2}') == 0 ]] || return 1
  pgrep -f 'xcodebuild|swift-test|swift-build|benchmark_routes' >/dev/null && return 1
  (( $(sysctl -n vm.loadavg | awk '{printf "%d", $2}') < 4 ))
}
deadline=$(( $(date +%s) + 1800 ))
until ready; do
  (( $(date +%s) < deadline )) || { echo "GAVE UP $(date +%T): not on mains power and quiet within 30 minutes; no request sent"; exit 2; }
  sleep 15
done
echo "=== live round $(date '+%F %T') power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/") load=$(sysctl -n vm.loadavg)"
python3 Scripts/benchmark_routes.py --app "$APP" --device "$DEVICE" --output "$HERE/L1" --scenarios live-now \
  --warm 1 --cold 1 --maximum-limit-ms 0 --request-budget 100 > "$HERE/L1.log" 2>&1
live_status=$?
echo "live exit $live_status, requests $(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$HERE/L1/transport.json" 2>/dev/null)"
grep -E 'completed|server wait split' "$HERE/L1.log"
echo "=== done $(date +%T)"
(( live_status == 0 )) || exit 3
