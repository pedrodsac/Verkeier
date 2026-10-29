#!/bin/zsh
# Replays every capture with the original and the trimmed bodies, ABBA order per capture.
# usage: batch.sh <build-label> <app> <reps> [capture names...]
set -u
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad/cand12a
C=~/Developer/Verkeier-captures
BUILD=${1:?label}; APP=${2:?app}; REPS=${3:?reps}; shift 3
typeset -A DIR SCEN SHAPE
DIR=(st-L1 $C/server-timing-2026-10-20/L1 s7-L1 $C/step7-2026-10-20/L1 s7-L2 $C/step7-2026-10-20/L2
     s7-L3 $C/step7-2026-10-20/L3 c28-now $C/cand-28-live-2026-10-19/live-now
     c28-rev $C/cand-28-live-2026-10-19/live-reverse c28-esch $C/cand-28-live-2026-10-19/live-esch
     st22-L2 $C/server-timing-2026-10-22/L2)
SCEN=(c28-rev live-reverse c28-esch live-esch)
SHAPE=(c28-now one c28-rev one c28-esch one)
if (( $# )); then names=($@); else names=(st-L1 s7-L1 s7-L2 s7-L3 c28-now c28-rev c28-esch st22-L2); fi
for rep in $(seq 1 $REPS); do
  for name in $names; do
    if (( rep % 2 )); then arms=(orig trim); else arms=(trim orig); fi
    for arm in $arms; do
      cap=${DIR[$name]}; [[ $arm == trim ]] && cap=$S/captures/$name
      $S/tools/replay.sh $APP $cap ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $S/runs/$BUILD/$name-$arm-$rep
      sleep 20
    done
  done
done
echo "ALLDONE $BUILD"
