#!/bin/zsh
# Offline (no ATP) latency replay of one capture, original or trimmed.
# usage: replay.sh <app> <capture-dir> <scenario> <three|one> <out-dir>
# APPROX=1 adds --replay-approximate. The epoch is the capture's priming planningTime.
set -uo pipefail
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
APP=${1:?app}; CAP=${2:?capture dir}; SCENARIO=${3:?scenario}; SHAPE=${4:?three|one}; OUT=${5:?out dir}
[[ -e $OUT/samples.json ]] && { echo "exists: $OUT"; exit 0; }
mkdir -p $OUT
epoch=$(python3 -I -c "import json,sys; print(repr(json.load(open(sys.argv[1]))[0]['planningTime']))" $CAP/samples.json)
case $SHAPE in three) counts=(--warm 1 --cold 1);; one) counts=(--warm 0 --cold 0);; esac
approx=(); [[ ${APPROX:-0} == 1 ]] && approx=(--replay-approximate)
cd ~/Developer/Verkeier
# Wait up to 3 minutes for the 1-minute load to drop below 6.
for i in {1..18}; do (( $(sysctl -n vm.loadavg | awk '{print int($2)}') < 6 )) && break; sleep 10; done
echo "$(date +%H:%M:%S) $OUT epoch $epoch load=$(sysctl -n vm.loadavg) $(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")"
python3 Scripts/benchmark_routes.py --app $APP --device $DEVICE --output $OUT --scenarios $SCENARIO $counts \
  --maximum-limit-ms 0 --request-budget 0 --capture-directory $CAP/network --bike-fixture $CAP/bike-snapshot.json \
  --epoch $epoch --replay-latency $approx > $OUT/run.log 2>&1
rc=$?
echo "$(date +%H:%M:%S) exit $rc"
exit $rc
