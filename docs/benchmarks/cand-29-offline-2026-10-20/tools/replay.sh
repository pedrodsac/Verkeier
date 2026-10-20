#!/bin/zsh
# Offline (no ATP) replay of one recorded capture with one arm.
# usage: replay.sh <capture-dir> <scenario> <samples: three|one> <arm: control|c29|c29cap4|...> <out-dir>
# Arms are selected with the engine environment variable CAND29 (SIMCTL_CHILD_CAND29); PASS_DEBUG=1 turns the log lines on.
set -uo pipefail
APP=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/a26d6e08-38cf-4a43-aeea-70a2e41c82cd/scratchpad/dd/Build/Products/Release-iphonesimulator/Verkeier.app
DEVICE=F726825E-2DB4-4F45-A51C-DBA5AA0E2664
CAP=${1:?capture dir}; SCENARIO=${2:?scenario}; SHAPE=${3:?three|one}; ARM=${4:?arm}; OUT=${5:?out dir}
[[ -e $OUT/samples.json ]] && { echo "exists: $OUT"; exit 0; }
mkdir -p $OUT
epoch=$(python3 -I -c "import json,sys; print(repr(json.load(open(sys.argv[1]))[0]['planningTime']))" $CAP/samples.json)
case $SHAPE in three) counts=(--warm 1 --cold 1);; one) counts=(--warm 0 --cold 0);; esac
case $ARM in
  control) ;;
  c29) export SIMCTL_CHILD_CAND29=1;;
  c29cap*|c29arr) export SIMCTL_CHILD_CAND29=${ARM#c29};;
  *) echo "unknown arm $ARM"; exit 2;;
esac
[[ ${PASS_DEBUG:-0} == 1 ]] && export SIMCTL_CHILD_PASS_DEBUG=1
cd ~/Developer/Verkeier
echo "$(date +%H:%M:%S) $CAP $ARM epoch $epoch lpm=$(pmset -g | awk '/lowpowermode/ {print $2}') load=$(sysctl -n vm.loadavg)"
python3 Scripts/benchmark_routes.py --app $APP --device $DEVICE --output $OUT --scenarios $SCENARIO $counts \
  --maximum-limit-ms 0 --request-budget 0 --capture-directory $CAP/network --bike-fixture $CAP/bike-snapshot.json \
  --epoch $epoch --replay-latency --replay-approximate > $OUT/run.log 2>&1
rc=$?
echo "$(date +%H:%M:%S) $ARM exit $rc"
exit $rc
