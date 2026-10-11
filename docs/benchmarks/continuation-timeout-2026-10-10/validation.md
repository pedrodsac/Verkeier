# Continuation timeout correction — 10 October 2026

The Gromscheed → Konrad Adenauer query is anchored at 20:11 Luxembourg time on
10 October. The installed Luxembourg timetable and pedestrian graph are used
with the production view model, routing adapter and rendered route sheet.
ATP transport is recorded/empty fixture transport; these numbers do not establish
live-network or physical-device performance.

The first correction, MobiliteitKit `60a9e12`, restores conservative destination
pruning and indexes block successors and continuation preparation. Release
measurements were 1,521 ms warm and 2,000 ms in a fresh app process. The priming
operation also passed the 5,000 ms harness gate. Each category has one measured
sample, so this is a regression spot check rather than a distribution estimate.
The paired pre-correction cold sample was 2,371 ms; Debug reproduced the reported
timeout at 30,655 ms. The app's normal timeout remains 15 seconds.

The final pin `ff99a77` also restores final-boarding-round pruning while following
reverse continuation links. This avoids globally admitting unrelated alighting
stops whenever any timetable trip has a block. The fixture suite checks compact
and reference kernels, explicit and block continuation chains, and an unrelated
branch near a continuation boundary that must still require another boarding.

All 244 package tests passed. The installed-feed replay confirms the 20:33:20
line 7 from Luxexpo remains aboard as line 25 at Poutty Stein, arriving at Konrad
Adenauer at 20:39:10 with zero transfers. The Gromscheed corridor replay also
passed. Release timing evidence beside this document is from the first
correction; final-pin validation is recorded below when completed.
