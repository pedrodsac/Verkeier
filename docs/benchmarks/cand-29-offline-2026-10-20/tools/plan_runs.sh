#!/bin/zsh
# Diagnostic (PASS_DEBUG) replays, priming-only shape, for every capture and arm. Aborted runs are expected for candidate arms.
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/a26d6e08-38cf-4a43-aeea-70a2e41c82cd/scratchpad
source $S/captures.sh
for entry in $CAPTURES; do
  name=${entry%%|*}; rest=${entry#*|}; dir=${rest%%|*}; rest=${rest#*|}; scen=${rest%%|*}
  for arm in control c29 c29arr; do
    PASS_DEBUG=1 $S/replay.sh $dir $scen one $arm $S/runs/plan/$name-$arm
    sleep 8
  done
done
echo ALLDONE
