#!/bin/zsh
# Terminus-kept replays: every capture once per arm, arm order rotating per capture.
# usage: V=1|2 batch_c.sh <rep> <arms...>
#   k10last     captures-k10last, no flags (unchanged engine)
#   k10lastfix  ROUTING_PASSLIST_CAP=10 (horizon change, a no-op with the terminus kept, + merge clamp)
#   k10lastgap  ROUTING_PASSLIST_CAP=10 + ROUTING_PASSLIST_GAP=1 (+ gap rule)
# Runs go to runs3 (V=1) or runs4 (V=2); V=2 covers only the captures the current engine can replay.
set -u
B=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/8d981c59-7668-4d73-9186-d468fc2578fe/scratchpad/passlist
REP=${1:?rep}; shift; ARMS=($@)
RUNS=$B/runs$(( ${V:?} + 2 ))
typeset -A SCEN SHAPE
SCEN=(c28-rev live-reverse c28-esch live-esch)
SHAPE=(c28-now one c28-rev one c28-esch one)
default="st-L1 s7-L1 s7-L2 s7-L3 c28-now c28-rev c28-esch st22-L2"; [[ $V == 2 ]] && default="s7-L1 c28-esch"
names=(${=NAMES:-$default})
export APPROX=1 V
i=0
for name in $names; do
  n=${#ARMS}; rotated=(${ARMS[$(( i % n + 1 )),-1]} ${ARMS[1,$(( i % n ))]}); i=$((i+1))
  for arm in $rotated; do
    set_name=${${arm%fix}%gap}; capk=""; gap=""
    [[ $arm == *fix || $arm == *gap ]] && capk=$(print -r -- $set_name | sed -E 's/^[kf]([0-9]+).*/\1/')
    [[ $arm == *gap ]] && gap=1
    GAP=$gap $B/tools/replay_c.sh $B/captures-$set_name/$name ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $RUNS/$name-$arm-$REP $capk
    sleep 5
  done
done
echo "ALLDONE $REP"
