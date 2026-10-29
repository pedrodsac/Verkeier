#!/bin/zsh
# Live A/B for CAND-28b (wide line filters split into parallel parts). A = engine 1d0ce96,
# B = 1d0ce96 + split. About 285 ATP requests in all, capped per run by --request-budget.
# Stops at the first failed run. Writes only below $S/live.
set -u
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad/s56
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
cd ~/Developer/Verkeier || exit 2
[[ $(pmset -g | awk '/lowpowermode/ {print $2}') == 0 ]] || { echo "REFUSED: Low Power Mode is on"; exit 2; }
runs=(
  "1 A live-now three 100"
  "2 B live-now three 100"
  "3 B live-now one 40"
  "4 A live-now one 40"
  "5 A live-reverse one 40"
  "6 B live-reverse one 40"
)
for spec in $runs; do
  parts=(${=spec}); n=$parts[1]; arm=$parts[2]; scenario=$parts[3]; shape=$parts[4]; budget=$parts[5]
  out=$S/live/$n-$arm-$scenario
  [[ -e $out ]] && { echo "exists: $out"; continue; }
  case $shape in three) counts=(--warm 1 --cold 1);; one) counts=(--warm 0 --cold 0);; esac
  app=$(ls -d $S/arms/$arm/dd/Build/Products/Release-iphonesimulator/*.app | head -1)
  for i in {1..12}; do (( $(sysctl -n vm.loadavg | awk '{print int($2)}') < 4 )) && break; sleep 10; done
  echo "=== $n $arm $scenario $shape $(date +%T) load=$(sysctl -n vm.loadavg) power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")"
  python3 Scripts/benchmark_routes.py --app "$app" --device $DEVICE --output $out --scenarios $scenario $counts \
    --maximum-limit-ms 0 --request-budget $budget > $out.log 2>&1
  rc=$?
  echo "exit $rc requests $(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' $out/transport.json 2>/dev/null) $(date +%T)"
  grep -E 'completed|server wait split' $out.log | head -6
  (( rc == 0 )) || { echo "STOPPED after run $n"; exit 3; }
  sleep 20
done
echo "=== done $(date +%T)"
