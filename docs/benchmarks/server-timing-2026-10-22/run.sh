#!/bin/zsh
# One live `live-now` round (priming, warm, cold; about 81 ATP requests) with the relay's
# Server-Timing header, approved by the owner at 18:49 on 2026-10-22 to run right now, during
# the evening slow period. It refuses to run only while Low Power Mode is on. It waits up to
# 3 minutes for no other build/benchmark job and a quiet machine, then runs anyway and says so.
# ALLOW_BATTERY=1 (owner, 2026-10-22) skips the mains-power check; the power source is printed.
# Writes only below this script's directory. Exit: 0 done, 2 refused, 3 the run failed.
set -u
export ALLOW_BATTERY=1
HERE=${0:A:h}
APP=/Users/pedoataidecordeiro/Developer/Verkeier-captures/server-timing-2026-10-20/app/Verkeier.app  # build fa5833b, engine 00078b6; not rebuilt
REPO=/Users/pedoataidecordeiro/Developer/Verkeier
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
cd "$REPO" || exit 2
[[ -d "$APP" && ! -e "$HERE/L1" ]] || { echo "REFUSED: no app, or L1 already exists"; exit 2; }

[[ $(pmset -g | awk '/lowpowermode/ {print $2}') == 0 ]] || { echo "REFUSED: Low Power Mode is on; no request sent"; exit 2; }
ready() {
  [[ ${ALLOW_BATTERY:-0} == 1 ]] || pmset -g batt | head -1 | grep -q "AC Power" || return 1
  pgrep -f 'xcodebuild|swift-test|swift-build|benchmark_routes' >/dev/null && return 1
  (( $(sysctl -n vm.loadavg | awk '{printf "%d", $2}') < 4 ))
}
deadline=$(( $(date +%s) + 180 ))
forced=0
until ready; do
  if (( $(date +%s) >= deadline )); then
    forced=1
    echo "NOT QUIET after 3 minutes ($(date +%T)); running anyway as the owner asked: load=$(sysctl -n vm.loadavg) jobs=$(pgrep -fl 'xcodebuild|swift-test|swift-build|benchmark_routes' | tr '\n' ';')"
    break
  fi
  sleep 15
done
echo "=== live round $(date '+%F %T') forced=$forced power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/") load=$(sysctl -n vm.loadavg)"
python3 Scripts/benchmark_routes.py --app "$APP" --device "$DEVICE" --output "$HERE/L1" --scenarios live-now \
  --warm 1 --cold 1 --maximum-limit-ms 0 --request-budget 100 > "$HERE/L1.log" 2>&1
live_status=$?
echo "live exit $live_status, requests $(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$HERE/L1/transport.json" 2>/dev/null)"
grep -E 'completed|server wait split' "$HERE/L1.log"
echo "=== done $(date +%T)"
(( live_status == 0 )) || exit 3
