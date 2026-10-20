#!/bin/zsh
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/a26d6e08-38cf-4a43-aeea-70a2e41c82cd/scratchpad
source $S/captures.sh
for entry in $CAPTURES; do
  name=${entry%%|*}; rest=${entry#*|}; dir=${rest%%|*}; rest=${rest#*|}; scen=${rest%%|*}
  PASS_DEBUG=1 $S/replay.sh $dir $scen one c29cap4 $S/runs/plan/$name-c29cap4
  sleep 8
done
echo ALLDONE
