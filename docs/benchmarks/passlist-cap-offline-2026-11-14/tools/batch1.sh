#!/bin/zsh
# v1 (engine a152c0f, the sweep-1 pin, + capped-passlist fix): replays every capture once per arm; arm order rotates per capture.
# usage: batch2.sh <rep> <arms...>   ("k10" = captures-k10 on unchanged code; "k10fix" = captures-k10 with ROUTING_PASSLIST_CAP=10)
set -u
B=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/8d981c59-7668-4d73-9186-d468fc2578fe/scratchpad/passlist
REP=${1:?rep}; shift; ARMS=($@)
typeset -A SCEN SHAPE
SCEN=(c28-rev live-reverse c28-esch live-esch)
SHAPE=(c28-now one c28-rev one c28-esch one)
names=(${=NAMES:-st-L1 s7-L1 s7-L2 s7-L3 c28-now c28-rev c28-esch st22-L2})
i=0
for name in $names; do
  n=${#ARMS}; rotated=(${ARMS[$(( i % n + 1 )),-1]} ${ARMS[1,$(( i % n ))]}); i=$((i+1))
  for arm in $rotated; do
    set_name=${arm%fix}; capk=""
    [[ $arm == *fix ]] && capk=${${set_name#k}#f}
    $B/tools/replay1.sh $B/captures-$set_name/$name ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $B/runs1/$name-$arm-$REP $capk
    sleep 5
  done
done
echo "ALLDONE $REP"
