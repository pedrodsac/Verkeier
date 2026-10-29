#!/bin/zsh
# Offline (no ATP) replays for steps 5 and 6. usage: replay_batch.sh <batch> <reps> <variant...>
# A variant is ARM[:KNOB], for example A, B~ (B with --replay-approximate), C:utility.
set -u
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad/s56
R=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad/cand12a/tools/replay.sh
C=~/Developer/Verkeier-captures
BATCH=${1:?batch}; REPS=${2:?reps}; shift 2; variants=($@)
typeset -A DIR SCEN SHAPE
DIR=(st-L1 $C/server-timing-2026-10-20/L1 s7-L1 $C/step7-2026-10-20/L1 s7-L2 $C/step7-2026-10-20/L2
     s7-L3 $C/step7-2026-10-20/L3 c28-now $C/cand-28-live-2026-10-19/live-now
     c28-rev $C/cand-28-live-2026-10-19/live-reverse c28-esch $C/cand-28-live-2026-10-19/live-esch
     st22-L2 $C/server-timing-2026-10-22/L2
     L1A $C/cand-28b-live-2026-10-29/1-A-live-now L2B $C/cand-28b-live-2026-10-29/2-B-live-now
     L3B $C/cand-28b-live-2026-10-29/3-B-live-now L4A $C/cand-28b-live-2026-10-29/4-A-live-now
     L5A $C/cand-28b-live-2026-10-29/5-A-live-reverse L6B $C/cand-28b-live-2026-10-29/6-B-live-reverse)
SCEN=(c28-rev live-reverse c28-esch live-esch L5A live-reverse L6B live-reverse)
SHAPE=(c28-now one c28-rev one c28-esch one L3B one L4A one L5A one L6B one)
names=(${=CAPTURES:-st-L1 s7-L1 s7-L2 s7-L3 c28-now c28-rev c28-esch st22-L2})
for rep in $(seq 1 $REPS); do
  for name in $names; do
    order=($variants); (( rep % 2 )) || order=(${(Oa)variants})
    for v in $order; do
      arm=${v%%:*}; knob=${v#*:}; [[ $knob == $v ]] && knob=""
      approx=0; [[ $arm == *~ ]] && { approx=1; arm=${arm%\~}; }
      app=$(ls -d $S/arms/$arm/dd/Build/Products/Release-iphonesimulator/*.app | head -1)
      label=${v//:/-}; label=${label//\~/x}
      out=$S/replays/$BATCH/$name-$label-$rep
      typeset -a envs; envs=()
      case $knob in
        utility|workers8) envs=(SIMCTL_CHILD_ROUTING_EXPERIMENT_WARMUP=$knob);;
        defer) envs=(SIMCTL_CHILD_ROUTING_EXPERIMENT_DEFER_REFINEMENT=1);;
      esac
      env $envs APPROX=$approx $R $app ${DIR[$name]} ${SCEN[$name]:-live-now} ${SHAPE[$name]:-three} $out
      sleep 20
    done
  done
done
echo "ALLDONE $BATCH"
