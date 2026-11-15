#!/bin/zsh
# Live A/B/C through the app. A = engine a152c0f, B = 830726a (queueing fix), C = B with discovery boards
# within 600 m of the destination skipped (scratch experiment). usage: live_abc.sh <round> <spec>...
# A spec is "N ARM SCENARIO three|one BUDGET". Stops at the first failed run. Writes only below $S/live.
set -u
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/706d6dc1-57e2-4a43-af7b-858b8970b3a7/scratchpad/hol
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
ROUND=${1:?round}; shift
cd ~/Developer/Verkeier || exit 2
[[ $(pmset -g | awk '/lowpowermode/ {print $2}') == 0 ]] || { echo "REFUSED: Low Power Mode is on"; exit 2; }
xcrun simctl bootstatus $DEVICE -b > /dev/null 2>&1
for spec in "$@"; do
  parts=(${=spec}); n=$parts[1]; arm=$parts[2]; scenario=$parts[3]; shape=$parts[4]; budget=$parts[5]
  out=$S/live/$ROUND/$n-$arm-$scenario
  [[ -e $out ]] && { echo "exists: $out"; continue; }
  mkdir -p $S/live/$ROUND
  case $shape in three) counts=(--warm 1 --cold 1);; one) counts=(--warm 0 --cold 0);; esac
  app=$(ls -d $S/arms/$arm/dd/Build/Products/Release-iphonesimulator/*.app | head -1)
  typeset -a envs; envs=()
  [[ $arm == C ]] && envs=(SIMCTL_CHILD_ROUTING_EXPERIMENT_DISCOVERY_SKIP_NEAR_DESTINATION_M=600)
  [[ $arm == D ]] && envs=(SIMCTL_CHILD_ROUTING_EXPERIMENT_TRANSFER_STOP_EARLIEST=1)
  for i in {1..12}; do (( $(sysctl -n vm.loadavg | awk '{print int($2)}') < 4 )) && break; sleep 10; done
  echo "=== $n $arm $scenario $shape $(date +%T) load=$(sysctl -n vm.loadavg) power=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")"
  env $envs python3 Scripts/benchmark_routes.py --app "$app" --device $DEVICE --output $out --scenarios $scenario $counts \
    --maximum-limit-ms 0 --request-budget $budget > $out.log 2>&1
  rc=$?
  echo "exit $rc requests $(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' $out/transport.json 2>/dev/null) $(date +%T)"
  grep -E 'completed' $out.log | head -3
  (( rc == 0 )) || { echo "STOPPED after run $n"; exit 3; }
  sleep 25
done
echo "=== done $(date +%T)"
