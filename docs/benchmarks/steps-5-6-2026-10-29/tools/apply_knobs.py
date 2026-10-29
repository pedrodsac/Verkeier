"""Experiment-only knobs for arm C (never committed). ROUTING_EXPERIMENT_WARMUP=utility|workers8 changes
only the warm-up scan; ROUTING_EXPERIMENT_DEFER_REFINEMENT=1 starts walking refinement after first render."""
import sys, unicodedata
from pathlib import Path
arm = Path(sys.argv[1]).resolve()
assert 'scratchpad/s56/arms/' in arm.as_posix()
def find(root, suffix):
    hits = [p for p in root.rglob('*.swift') if unicodedata.normalize('NFC', p.as_posix()).endswith(suffix)]
    assert len(hits) == 1, (suffix, hits); return hits[0]
def patch(path, old, new, count=1):
    s = path.read_text(); assert s.count(old) == count, (path, old, s.count(old)); path.write_text(s.replace(old, new))
eng = arm / 'MobiliteitKit'
patch(find(eng, 'Routing/RaptorTypes.swift'), '    static let maximumPatternWorkers = 10\n',
      '    static let maximumPatternWorkers = 10\n    @TaskLocal static var scanPriority: TaskPriority = .userInitiated\n')
patch(find(eng, 'Routing/RaptorPatternScan.swift'), 'addTask(priority: .userInitiated)', 'addTask(priority: scanPriority)', 3)
patch(find(eng, 'Routing/RaptorWalkingTransfers.swift'), 'addTask(priority: .userInitiated)', 'addTask(priority: scanPriority)')
patch(find(eng, 'Routing/JourneyPlanningSession+WalkingPreparation.swift'),
"""        let result = try await Raptor.search(snapshot: snapshot, query: query, access: access,
            egress: egress, patches: patches, walking: walking, profileHorizon: horizon)""",
"""        let knob = ProcessInfo.processInfo.environment["ROUTING_EXPERIMENT_WARMUP"] ?? ""
        let search = { try await Raptor.search(snapshot: snapshot, query: query, access: access,
            egress: egress, patches: patches, walking: walking, profileHorizon: horizon) }
        let result = knob == "utility" ? try await Raptor.$scanPriority.withValue(.utility) { try await search() }
            : knob == "workers8" ? try await Raptor.$activeProcessorCountOverride.withValue(8) { try await search() }
            : try await search()""")
app = arm / 'app'
calc = find(app, 'Features/Routes/Models/RoutePlannerModel+Calculation.swift')
patch(calc, """                if !didScheduleWalkingRefinement, !calculation.hasMoreOptions {
                    didScheduleWalkingRefinement = true
                    scheduleWalkingRouteRefinement(
                        calculation,
                        using: routeService,
                        from: origin,
                        to: destination.location,
                        requestGeneration: requestGeneration
                    )
                }""", """                if !didScheduleWalkingRefinement, !calculation.hasMoreOptions {
                    didScheduleWalkingRefinement = true
                    let destinationLocation = destination.location
                    let start = { [weak self] in
                        self?.scheduleWalkingRouteRefinement(
                            calculation,
                            using: routeService,
                            from: origin,
                            to: destinationLocation,
                            requestGeneration: requestGeneration
                        )
                    }
                    if ProcessInfo.processInfo.environment["ROUTING_EXPERIMENT_DEFER_REFINEMENT"] == "1" {
                        experimentDeferredRefinement = start
                    } else {
                        start()
                    }
                }""")
patch(calc, """        routeDiagnostics?.record(.firstRender, since: published)""", """        routeDiagnostics?.record(.firstRender, since: published)
        if let deferred = experimentDeferredRefinement {
            experimentDeferredRefinement = nil
            deferred()
        }""")
patch(find(app, 'Features/Routes/Models/RoutePlannerModel.swift'), '    var walkingRefinedOptionIDs: Set<String> = []\n',
      '    var walkingRefinedOptionIDs: Set<String> = []\n    @ObservationIgnored var experimentDeferredRefinement: (() -> Void)?\n')
print('knobs applied', arm)
