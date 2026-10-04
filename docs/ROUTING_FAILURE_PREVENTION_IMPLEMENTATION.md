# Routing failure prevention implementation

Implemented 1 October 2026 in MobiliteitKit and Verkéier. The original [49-case plan](ROUTING_FAILURE_PREVENTION_PLAN.md) remains the design and historical audit; this document records the shipped behavior and executable regression map.

## Behavior

The router validates immutable feed identity, service date, ordered stop occurrences, pickup/drop-off permissions, physical adjacency, chronology, transfer rules and hard constraints before dominance and again before publication. Walking refinement uses the same checks and recalculates the residual transfer requirement. Failed staged imports preserve the previously installed timetable. Exact frequency instances replace their template rather than creating an extra phantom departure.

Every actual transfer requires `D - A >= max(feed minimum, user minimum, walking + boarding buffer)`. The legacy shortfall preference remains decodable but grants no tolerance. Estimated delays cannot prove boarding after the scheduled deadline; fresh direct reports can. Sparse overlays are resolved across the full trip, with a 120-second observation limit and two-hour delay/propagation limits. Contradictory evidence quarantines the instance. Merging preserves fresh reports across concurrent board completion order and does not renew their timestamps with extrapolations.

Trip identity includes feed generation, trip/frequency ID and service date. Public legs carry boarding/alighting sequences and boarding-specific headsigns; app leg identifiers include instance and occurrence. Search dominance compares complete used-instance history and incoming occurrence so that a label cannot erase different future eligibility. Both kernels retain the same bounded 48-label profile and quotas.

Only explicit linked GTFS type-4 rules produce stay-aboard segments; type 5 wins a conflicting equally scoped rule. Block and line identifiers grant no continuation permission. Continuations operate in the same vehicle-change round, work with zero allowed transfers, and retain both route numbers. Timeline, sharing and VoiceOver say “Stay aboard.” Intermediate stop boarding accessibility is unnecessary for a seated continuation; vehicle and actual boarding/alighting access remain mandatory.

Main suggestions use a separate 120-second material-benefit policy, preserve meaningful accessibility/mode/departure tradeoffs, and reserve an independently catchable competitive first-vehicle fallback. At most two options share the first vehicle when such a fallback exists. Minor endpoint choices collapse after validation. A verified walk can also replace a feeder bus when it catches the same remaining trip instances, reaches the same alighting occurrences, leaves home no earlier, arrives no later, and adds at most five minutes of walking. The first remaining vehicle may be boarded at a different validated occurrence; all subsequent boarding actions match exactly. An explicit less-walking preference preserves the feeder when it saves walking. This rule applies to the complete profile and every session publication, including paging and refresh. Exact dominance removes demonstrably removable cycles; necessary reversals, barriers, circular rides and distinct same-line vehicles remain eligible. An eligible faster direct walk can become the recommendation, including when either endpoint is a selected stop. A valid previous recommendation survives changes smaller than the 60-second score margin; invalidation switches immediately.

Result sessions freeze realtime evidence within a paging generation and recheck its observation age before every snapshot/refinement publication, track exploration separately from selected suggestions, backfill after deduplication and reject obsolete opaque cursors. Refresh rebases the generation and invalidations atomically. App services reuse the package session for the same request, replace it when the installed feed changes, and reject superseded calculation/refinement callbacks. The app consumes authoritative accumulated snapshots and retains a valid manual choice.

## Regression map

All names below refer to Swift Testing tests in MobiliteitKit unless prefixed `App`. `Search`, `Policy`, `Realtime`, `Lifecycle`, `Oracle` and `Constraints` denote the corresponding `RoutingPrevention…Tests` suites. Parameterized tests cover their boundary and legitimate-exception variants.

| Case | Executable regression(s) |
|---|---|
| 01 | Search.scannerNeverReboardsUsedInstanceButAllowsAnotherVehicleOnSameLine |
| 02 | Oracle.redundantCycleAndNecessaryReverseInterchange (shortcut allowed/forbidden) |
| 03 | Oracle.redundantCycleAndNecessaryReverseInterchange |
| 04 | Oracle.redundantCycleAndNecessaryReverseInterchange; Search.circularRideRetainsBoardingOccurrenceAndHeadsign |
| 05 | Search.scannerNeverReboardsUsedInstanceButAllowsAnotherVehicleOnSameLine |
| 06 | Policy.materialTransferBenefit; oneMinuteTransferBenefitDoesNotCrowdOutDirectService; RoutingWastefulConnectionTests.stayOn326Unless311IsNeededToCatch18 |
| 07 | Policy.needlessWaitAndSlowerChangeLoseWhileSoleRuralServiceSurvives; RoutingWastefulConnectionTests.stayOn326Unless311IsNeededToCatch18 |
| 08 | Policy.exactDominanceKeepsLaterDepartureAndLowerWalking |
| 09 | Lifecycle.twentyAlternatingPagesMakeStrictProgressWithoutDuplicates; routePlannerCollapsesExactTripsAndKeepsTheSafestTransfer |
| 10 | Policy.tinyEndpointVariationKeepsAccessibleException |
| 11 | Search.strictMinimumBoundary; genericSameStopMinimumCannotBeBypassed |
| 12 | Constraints.pathwayMovementAndTotalTransferMinimum; Search.verifiedContinuationUsesZeroTransfers |
| 13 | Search.strictMinimumBoundary (119, 119.999, 120, 120.001, 121 seconds) |
| 14 | Policy.needlessWaitAndSlowerChangeLoseWhileSoleRuralServiceSurvives |
| 15 | Policy.exactDominanceKeepsLaterDepartureAndLowerWalking; Policy.needlessWaitAndSlowerChangeLoseWhileSoleRuralServiceSurvives; arrivalDeadlineKeepsLatestDepartureBeyondEightEarlyTrips |
| 16 | Policy.materialTransferBenefit; defaultTransferDepthFindsThreeVehicleJourney |
| 17 | Oracle.inferiorBoardingVersusRequiredWalkingDetour (with/without barrier); RoutingWastefulConnectionTests.walkTo850WhenItLeavesHomeLater; App.RoutingScreenshotReplayTests.eveningConnectionsAvoidRedundant326 |
| 18 | Policy.longWalkForTwoMinutesLosesButAccessibleVariantSurvives |
| 19 | Policy.fifteenMinuteWalkBeatsTwentyFiveMinuteTwoBusRide; App.JourneyPlanningIntegrationTests.fasterWalkingRecommendationPassesThrough |
| 20 | Oracle.inferiorBoardingVersusRequiredWalkingDetour; Search.forbiddenPickupOrDropoff |
| 21 | Oracle.alightingChoiceUsesActualEgressTime (30/180-second egress) |
| 22 | Search.verifiedContinuationUsesZeroTransfers; Search.linkedMidnightUsesCorrectServiceDates |
| 23 | App.RouteContinuationTests.packageContinuationMapsToAppWithoutLostBoundary; timelineShareAndAccessibilitySayStayAboard; ordinaryChangeStillRequiresTransferMinimum |
| 24 | Search.circularRideRetainsBoardingOccurrenceAndHeadsign |
| 25 | Search.circularRideRetainsBoardingOccurrenceAndHeadsign; Oracle.generatedTimetablesMatchExhaustiveFeasibleParetoOutcomes |
| 26 | Realtime.sparsePatchCannotConfuseRepeatedStopOccurrences; RealtimeOccurrenceTests.repeatedStopPredictionsApplyToTheCorrectOccurrence |
| 27 | Constraints.simultaneousVehiclesAndDisconnectedLegsCannotPublish; App.WalkingRouteRefinementTests.missedTransferIsInvalid; App.JourneyPlanningIntegrationTests.refinementFeedbackPreservesNativeTransit |
| 28 | Realtime.sparseDelayPropagatesAcrossScheduledFallbackEvents; contradictoryRecoveryAndExpiredEvidenceAreQuarantined |
| 29 | Realtime.sparseDelayPropagatesAcrossScheduledFallbackEvents; RealtimeOccurrenceTests.secondBoardImprovesAnAlreadyMatchedJourney; Realtime.concurrentBoardOrderPreservesFreshDirectReport |
| 30 | Realtime.delayedPastBoardingNeedsConservativeProof; realtimeDelayMakesABusCatchableAfterWalkingToTheStop |
| 31 | realtimeDelayCanCreateAnOtherwiseImpossibleTransfer; RealtimeAcquisitionIntegrationTests.nextWaveFindsADelayedTransferOutsideStaticWinners |
| 32 | Realtime.delayedPastBoardingNeedsConservativeProof; contradictoryRecoveryAndExpiredEvidenceAreQuarantined; Lifecycle.expiredFrozenEvidenceCannotSurviveSnapshotOrPaging |
| 33 | Lifecycle.refreshHysteresisAndCancellation; App.RouteOptionDeduplicationTests.preservesManualSelection |
| 34 | Policy.independentFallbackAndSensibleEqualTimeOrdering |
| 35 | Policy.independentFallbackAndSensibleEqualTimeOrdering |
| 36 | Policy.independentFallbackAndSensibleEqualTimeOrdering (catchability and poor-fallback controls) |
| 37 | Constraints.simultaneousVehiclesAndDisconnectedLegsCannotPublish |
| 38 | Oracle.redundantCycleAndNecessaryReverseInterchange |
| 39 | Search.exactPlatformTransferScope; Constraints.pathwayMovementAndTotalTransferMinimum |
| 40 | Constraints.pathwayMovementAndTotalTransferMinimum; usefulInterchangeBeyondOldRadiusUsesVerifiedWalkingBudget |
| 41 | Search.removedCalendarDayCannotBeActivatedByLiveEvidence; streamedImportSupportsArchiveTablesAndQueries |
| 42 | Search.linkedMidnightUsesCorrectServiceDates; RealtimeOccurrenceTests.afterMidnightPredictionsKeepTheGTFSServiceDate |
| 43 | Search.linkedMidnightUsesCorrectServiceDates; Search.daylightSavingServiceInstantsRemainChronological; RealtimeOccurrenceTests.daylightSavingTransitionKeepsTheGTFSServiceDate |
| 44 | Search.cancelledContinuationNeverPublishesEitherEnd; Lifecycle.refreshHysteresisAndCancellation (stale cursor and cancelled-page controls); Constraints.exactFrequencyInstancesDoNotPublishTemplatePhantom |
| 45 | Search.forbiddenPickupOrDropoff; RealtimeOccurrenceTests.skippedStopPreventsAlightingButDoesNotCancelTheVehicle |
| 46 | Constraints.requiredVehicleAccessIsNotInferredFromUnknown; continuationRequiresVehicleButNotInterchangeAccess; stairsOnlyStationConnectionFailsRequiredWheelchairQuery |
| 47 | Constraints.requiredVehicleAccessIsNotInferredFromUnknown; walkingBudgetRemainsHardDuringPublication; Search.verifiedContinuationUsesZeroTransfers; transferMinimumIncludesWalkingAndRefinementRecalculatesResidual |
| 48 | Lifecycle.shiftedAnchorRetainsStillCatchableInstances; refreshHysteresisAndCancellation; parallelPatternScanningIsDeterministic |
| 49 | Lifecycle.expiredFrozenEvidenceCannotSurviveSnapshotOrPaging; twentyAlternatingPagesMakeStrictProgressWithoutDuplicates; equalDepartureBoundariesBackfillNoncontiguousInitialSelection; arriveByPagingRetainsDeadline |

Validate these references with `python3 Scripts/check_routing_prevention_coverage.py --package <existing MobiliteitKit checkout>`. This checks names and all 49 IDs; passing the Swift suites establishes the actual assertions.

The independent oracle exhaustively enumerates 32 seeded tiny networks and compares feasible Pareto outcomes against the router. `RaptorCompactProfileTests` compares every insertion over 4,000 generated candidates; `ROUTING_VERIFY_KERNEL=1` additionally compares complete compact/reference scans. These complement rather than substitute for the case regressions.

App coverage also includes continuation persistence/geometry replacement, invalid persisted continuation metadata, native transit preservation after walking feedback, authoritative replacement snapshots, and superseded refinement tokens.

## Delivery evidence

- Package source milestone: `b016a8c`; acceptance fixtures: `42ceb77`; selected-stop walking and installed replay update: `b9546df`; publication expiry: `6492c36`; supplemental installed-feed tests: `8bf4741`.
- Offline package gate: **141 tests in 16 suites**, with `ROUTING_VERIFY_KERNEL=1`; live-download test requires explicit `ROUTING_LIVE_DOWNLOAD_TESTS=1` and remains off.
- App integration against runtime revision `6492c36` (identical production sources in final remote pin `8bf4741`): **48 tests in 10 suites**; Release simulator build succeeded. The local package override used during development is removed.
- Five existing installed-feed replay tests and the supplemental circular/midnight/overflow/first-service/last-service/cancellation replay pass without downloading data.
- Commands and concise gate output: [verification.txt](benchmarks/routing-prevention-2026-10-01/verification.txt).
- Release rendered gate: **300 timed operations**, all 20 warm/cold p95 groups pass. Worst p95 **4.787 seconds**, including the full realtime deadline. Peak simulator resident memory **987.3 MiB**. [Measurements and provenance](benchmarks/routing-prevention-2026-10-01/validation.md).

Reproduce ordinary tests with `ROUTING_VERIFY_KERNEL=1 swift test` in the package and the plan's simulator command in the app. Installed replay uses `ROUTING_BENCHMARK_DATABASE` pointing at a previously installed database. The old Breedewues assertion allowed a 405-second gap against a 450-second requirement. The replay now verifies every connection against its scoped rule and measured movement; a valid occurrence using the same trip pair remains eligible. Six installed-feed replay tests pass on feed generation 3 (24 September–12 December 2026), without downloading data. `InstalledRoutingPreventionReplayTests.circularMidnightFirstLastAndCancellation` derives active trip occurrences from the feed, validates every returned itinerary against the immutable snapshot and verifies that cancelling a real selected instance removes it.

## Screenshot follow-up

The evening screenshots exposed a feeder that exact Pareto dominance retained because it saved a small amount of walking. MobiliteitKit `fe43ae9` now removes that feeder when a validated walk can catch the same remaining services and leave home no earlier. The app pins the tested remote revision. New regressions cover staying on the 326, walking to the 850 at another stop, legitimate transfer/walking exceptions, paging and refresh. The real pedestrian-graph replay reproduces the old failure and confirms its removal. [Behavior, replay and follow-up verification](benchmarks/routing-prevention-screenshots-2026-10-01/validation.md).

## Luxexpo intermediate-transfer follow-up

MobiliteitKit `736bd29` also removes an intermediate vehicle when a validated
journey stays aboard a shared trip to a later alighting occurrence and catches
the same downstream trip instances. The replacement must leave no earlier,
arrive no later, preserve accessibility and preferred-mode participation, and
add at most five minutes of total walking. A less-walking preference preserves
an interchange that saves walking. Both the complete search profile and every
accumulated result-session snapshot apply this rule.

`RoutingWastefulConnectionTests` reproduces 322 → 325 → T1 surviving because
322 → T1 has a longer interchange walk. It covers the five-minute boundary,
unreachable walking, necessary 325 connections, walking budgets, arrive-by,
trip-instance/occurrence evidence, paging, refresh and a walking refinement
that restores the necessary 325. All 165 package tests pass with
`ROUTING_VERIFY_KERNEL=1`.

The app's opt-in `morningLuxexpoConnectionAvoidsRedundant325` replay uses the
installed generation-3 timetable, the real pedestrian graph, Gromscheed and
Philharmonie / Mudam on 4 October 2026, with an 11:16 departure anchor. In this
schedule, trip `24262729` arrives at Gare routière Luxexpo at 11:27:10. The
137-second pedestrian route misses tram `24320542` at 11:29:20 by seven
seconds, so the 325 legitimately catches an earlier tram. A controlled,
fresh realtime fixture moves only the 322 arrival to 11:26:50 and verifies
that 322 → T1 catches that same tram and removes 322 → 325 → T1. This is
an offline schedule/control replay; the screenshot's original live evidence
was not supplied.

The app pins the tested remote revision. The Release iPhone 17 simulator
build and full test suite pass: 110 tests in 21 suites, with both morning
controls and the previous evening screenshot replay enabled.

## Contract limits

These regressions establish behavior under the feed/provider contracts; they cannot certify the physical operation of an elevator or a vehicle's future arrival. Unknown wheelchair evidence does not satisfy a required-access request. Feeds without explicit linked type-4 trip evidence receive ordinary valid transfers, not inferred through-service. A legacy custom realtime provider may hand off a prevalidated patch without observation timestamps; the production HAFAS provider supplies acquisition timestamps, which are bounded here. New providers should supply them too. Bounded search and acquisition coverage remain exposed in existing metrics; missing realtime is not cancellation or proof of exhaustive coverage. No remote telemetry was added.
