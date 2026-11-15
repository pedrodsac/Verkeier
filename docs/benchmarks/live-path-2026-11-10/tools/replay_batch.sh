#!/bin/zsh
# Offline (no ATP) replays for the board-queueing fix. usage: replay_batch.sh <batch> <reps> <variant...>
# A variant is an arm, with ~ for --replay-approximate (A~). Order alternates each repetition.
set -u
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/706d6dc1-57e2-4a43-af7b-858b8970b3a7/scratchpad/hol
R=$S/tools/replay.sh
C=~/Developer/Verkeier-captures
BATCH=${1:?batch}; REPS=${2:?reps}; shift 2; variants=($@)
typeset -A DIR SCEN SHAPE
DIR=(st22-L2 $C/server-timing-2026-10-22/L2 s7-L2 $C/step7-2026-10-20/L2
     st-L1 $C/server-timing-2026-10-20/L1 s7-L1 $C/step7-2026-10-20/L1 s7-L3 $C/step7-2026-10-20/L3
     c28-now $C/cand-28-live-2026-10-19/live-now c28-rev $C/cand-28-live-2026-10-19/live-reverse
     c28-esch $C/cand-28-live-2026-10-19/live-esch
     L2B $C/cand-28b-live-2026-10-29/2-B-live-now L3B $C/cand-28b-live-2026-10-29/3-B-live-now
     L6B $C/cand-28b-live-2026-10-29/6-B-live-reverse)
SCEN=(L6B live-reverse c28-rev live-reverse c28-esch live-esch)
SHAPE=(L3B one L6B one c28-now one c28-rev one c28-esch one)
names=(${=CAPTURES:-L2B L3B L6B})
for rep in $(seq 1 $REPS); do
  for name in $names; do
    order=($variants); (( rep % 2 )) || order=(${(Oa)variants})
    for v in $order; do
      arm=$v; approx=0; [[ $arm == *~ ]] && { approx=1; arm=${arm%\~}; }
      app=$(ls -d $S/arms/$arm/dd/Build/Products/Release-iphonesimulator/*.app | head -1)
      label=${v//\~/x}
      out=$S/replays/$BATCH/$name-$label-$rep
      typeset -a envs; envs=()
      # Arm C is the scratch experiment: skip discovery boards within 600 m of the destination.
      [[ $arm == C ]] && envs=(SIMCTL_CHILD_ROUTING_EXPERIMENT_DISCOVERY_SKIP_NEAR_DESTINATION_M=600)
      env $envs APPROX=$approx $R $app ${DIR[$name]} ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $out
      sleep 20
    done
  done
done
echo "ALLDONE $BATCH"
