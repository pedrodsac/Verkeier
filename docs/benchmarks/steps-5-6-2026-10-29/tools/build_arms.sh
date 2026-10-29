#!/bin/zsh
S=/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad/s56
set -e
python3 -I $S/tools/make_arm.py $S/arms/A c9dea17 1d0ce96
python3 -I $S/tools/make_arm.py $S/arms/B c9dea17 1d0ce96 \
  "Sources/MobilitéitKit/Routing/HafasRealtimeRoutingProvider+LineCoverage.swift" \
  "Sources/MobilitéitKit/Routing/HafasRealtimeRoutingProvider+Acquisition.swift" \
  "Sources/MobilitéitKit/Routing/RealtimeBoardRequestScheduler.swift"
for arm in A B; do
  cd $S/arms/$arm/app
  xcodebuild -project Verkeier.xcodeproj -scheme Verkeier -configuration Release \
    -destination "platform=iOS Simulator,id=F726825E-2DB4-4F45-A51C-DBA5AA0E2664" \
    -derivedDataPath $S/arms/$arm/dd ENABLE_CODE_COVERAGE=NO build > $S/arms/$arm/build.log 2>&1
  echo "$arm build exit $? coverage-flags $(grep -c profile-coverage-mapping $S/arms/$arm/build.log)"
done
