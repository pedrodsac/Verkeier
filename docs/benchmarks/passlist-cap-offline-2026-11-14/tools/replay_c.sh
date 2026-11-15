#!/bin/zsh
# Offline (no ATP) latency replay of one capture on the terminus-kept builds (v1c = a152c0f, v2c = d98fb57,
# both with the horizon change, merge clamp and gap rule, each behind its environment flag).
# usage: V=1|2 replay_c.sh <capture-dir> <scenario> <three|one> <out-dir> [cap] ; GAP=1 adds the gap rule
set -uo pipefail
B=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/8d981c59-7668-4d73-9186-d468fc2578fe/scratchpad/passlist
V=${V:?engine 1 or 2}
DEVICE=$(cat $B/device.txt)
APP=$B/dd${V}c/Build/Products/Release-iphonesimulator/Verkeier.app
CAP=${1:?capture dir}; SCENARIO=${2:?scenario}; SHAPE=${3:?three|one}; OUT=${4:?out dir}
CAPK=${5:-}; [[ -n $CAPK ]] && export SIMCTL_CHILD_ROUTING_PASSLIST_CAP=$CAPK
[[ ${GAP:-} == 1 ]] && export SIMCTL_CHILD_ROUTING_PASSLIST_GAP=1
[[ -e $OUT/samples.json ]] && { echo "exists: $OUT"; exit 0; }
mkdir -p $OUT
epoch=$(python3 -I -c "import json,sys; print(repr(json.load(open(sys.argv[1]))[0]['planningTime']))" $CAP/samples.json)
case $SHAPE in three) counts=(--warm 1 --cold 1);; one) counts=(--warm 0 --cold 0);; esac
APPROXFLAG=""; [[ ${APPROX:-0} == 1 ]] && APPROXFLAG="--replay-approximate"
export SIMCTL_CHILD_ROUTING_BENCHMARK_DATABASE=$B/db/gen5.sqlite
cd $B/v${V}c/app
for i in {1..18}; do (( $(sysctl -n vm.loadavg | awk '{print int($2)}') < 10 )) && break; sleep 10; done
echo "$(date +%H:%M:%S) $OUT cap=${CAPK:-none} gap=${GAP:-0} epoch $epoch load=$(sysctl -n vm.loadavg)"
python3 Scripts/benchmark_routes.py --app $APP --device $DEVICE --output $OUT --scenarios $SCENARIO $counts \
  --maximum-limit-ms 0 --request-budget 0 --capture-directory $CAP/network --bike-fixture $CAP/bike-snapshot.json \
  --epoch $epoch --replay-latency ${=APPROXFLAG:-} > $OUT/run.log 2>&1
rc=$?
echo "$(date +%H:%M:%S) exit $rc"
exit $rc
