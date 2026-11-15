#!/bin/zsh
# Replays on the real engine change (v3c = d98fb57 + passlistMaxStops request, gap rule, merge clamp; no flags).
# usage: batch_real.sh <rep>   arms: k10lastreal (terminus-kept captures), origreal (full captures)
# Runs go to runs6, next to symlinks of the unchanged engine's orig runs from runs4.
set -u
B=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/8d981c59-7668-4d73-9186-d468fc2578fe/scratchpad/passlist
REP=${1:?rep}
typeset -A SCEN SHAPE
SCEN=(c28-esch live-esch); SHAPE=(c28-esch one)
export APPROX=1 V=3
i=0
for name in s7-L1 c28-esch; do
  arms=(k10lastreal origreal); (( i % 2 )) && arms=(origreal k10lastreal); i=$((i+1))
  for arm in $arms; do
    set_name=${arm%real}
    $B/tools/replay_c.sh $B/captures-$set_name/$name ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $B/runs6/$name-$arm-$REP
    sleep 5
  done
done
echo "ALLDONE $REP"
