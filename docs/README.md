# Verkéier Docs

**Start here.** Navigation map for every doc in this directory.

## I need to know…

| Question | Read |
|---|---|
| What the app is and what it should do | `PRD.md` |
| How the code is layered and what lives where | `ARCHITECTURE.md` + root `AGENTS.md` |
| Service implementations and DI | `SERVICES.md` and current source |
| Which data sources exist and what they return | `DATA_SOURCES.md` |
| Code style, folder rules, forbidden patterns | `CODEBASE_RULES.md` |
| How GTFS updates work end-to-end | `GTFS_AUTO_UPDATE_PLAN.md` |
| Comprehensive feature roadmap (what to build next) | `FEATURE_ROADMAP.md` |
| Route quality work | `ROUTE_QUALITY_IMPLEMENTATION_PLAN.md` |
| Gromscheed → Konrad Adenauer comparison with mobiliteit.lu | `ROUTING_MOBILITEIT_COMPARISON.md` |
| Leave at, Arrive by, Earlier and Later behavior | `ROUTE_TIME_CONTROLS.md` |
| Preventing invalid, wasteful, unstable or duplicate journeys | `ROUTING_FAILURE_PREVENTION_PLAN.md` + `ROUTING_FAILURE_PREVENTION_IMPLEMENTATION.md` (behavior, 49-case regressions and verification) |
| Missing live updates on connecting trips | `ROUTING_LIVE_CONNECTIONS.md` |
| Router performance, simulator measurements and reproduction | `ROUTE_CALCULATION_PERFORMANCE.md` |
| UI lag, launch work and map update performance | `UI_PERFORMANCE.md` |

## Two-read orientation

1. Read `AGENTS.md` (root) — commands, layer rules, hard constraints.
2. Read `SERVICES.md` for service background, then check current source signatures.

After those two an agent can navigate any feature without guessing.

## Doc inventory

```
docs/
├── README.md                                      ← you are here
├── PRD.md                                         ← product requirements (anchor)
├── ARCHITECTURE.md                                ← layers, module layout, DI overview
├── SERVICES.md                                    ← implemented services + DI pattern
├── CODEBASE_RULES.md                              ← folder, size, forbidden/required rules
├── DATA_SOURCES.md                                ← ATP, GTFS, AVL contract details
├── GTFS_AUTO_UPDATE_PLAN.md                       ← GTFS update pipeline spec
├── FEATURE_ROADMAP.md                             ← comprehensive feature checklist
├── ROUTE_QUALITY_IMPLEMENTATION_PLAN.md          ← route quality design notes
├── ROUTING_FAILURE_PREVENTION_PLAN.md            ← current safeguards, gaps and 49-case regression plan
├── ROUTING_FAILURE_PREVENTION_IMPLEMENTATION.md  ← delivered behavior and regression traceability
├── ROUTE_CALCULATION_PERFORMANCE.md              ← implementation and measured five-second gate
└── benchmarks/route-performance-2026-09-30/      ← per-request timing evidence
```

## What this app is

Native SwiftUI iOS app for Luxembourg public transport. Apple Maps-style
full-screen MapKit map with a persistent draggable bottom sheet. Data from
ATP live data through a separate Cloudflare relay, a downloaded GTFS timetable,
and Ville de Luxembourg disruption XML. See current source for implemented
behavior; some design documents describe earlier phases.
