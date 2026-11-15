#!/bin/zsh
# Sends at most two board requests through the app to see whether ATP still answers 429.
# usage: quota_probe.sh <label> [wait seconds]
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/706d6dc1-57e2-4a43-af7b-858b8970b3a7/scratchpad/hol
label=${1:?label}; wait=${2:-0}
sleep $wait
out=$S/live/probes/$label
mkdir -p $S/live/probes
cd ~/Developer/Verkeier
app=$S/arms/B/dd/Build/Products/Release-iphonesimulator/Verkeier.app
python3 Scripts/benchmark_routes.py --app $app --device F726825E-2DB4-4F45-A51C-DBA5AA0E2664 --output $out --scenarios live-now --warm 0 --cold 0 --maximum-limit-ms 0 --request-budget 2 --live-concurrency 1 > $out.log 2>&1
echo "probe $label at $(date +%T): harness exit $?"
python3 -I -c 'import json,sys,collections; t=json.load(open(sys.argv[1])); print("requests", len(t), "statuses", dict(collections.Counter(r.get("status") for r in t)))' $out/transport.json 2>&1
