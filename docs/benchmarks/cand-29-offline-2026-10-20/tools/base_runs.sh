#!/bin/zsh
# Non-debug control replays (timing baseline): st-L1 three times, every other capture once; 25 s between runs.
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/a26d6e08-38cf-4a43-aeea-70a2e41c82cd/scratchpad
source $S/captures.sh
mkdir -p $S/runs/base
for rep in 1 2 3; do
  for entry in $CAPTURES; do
    name=${entry%%|*}; rest=${entry#*|}; dir=${rest%%|*}; rest=${rest#*|}; scen=${rest%%|*}; shape=${rest#*|}
    [[ $rep -gt 1 && $name != st-L1 && $name != s7-L1 ]] && continue
    $S/replay.sh $dir $scen $shape control $S/runs/base/$name-control-$rep
    sleep 25
  done
done
echo ALLDONE
