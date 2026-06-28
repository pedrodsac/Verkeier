# LuxTransit Docs

**Start here.** Navigation map for every doc in this directory.

## I need to know…

| Question | Read |
|---|---|
| What the app is and what it should do | `PRD.md` |
| How the code is layered and what lives where | `ARCHITECTURE.md` + root `CLAUDE.md` |
| Service protocols, method signatures, DI | `SERVICES.md` |
| Which data sources exist and what they return | `DATA_SOURCES.md` |
| Code style, folder rules, forbidden patterns | `CODEBASE_RULES.md` |
| What phases are planned / what is done | `MVP_CHECKLIST.md` |
| How GTFS updates work end-to-end | `GTFS_AUTO_UPDATE_PLAN.md` |
| Comprehensive feature roadmap (what to build next) | `FEATURE_ROADMAP.md` |
| Open bugs and feature opportunities (June audit) | `APP_AUDIT_FEATURE_CHECKLIST_2026-06-20.md` |
| Phased rollout plan from the audit | `superpowers/specs/2026-06-20-app-audit-rollout-design.md` |
| UI overhaul design decisions | `superpowers/specs/2026-06-13-ui-overhaul-design.md` |
| ATP platform-grouping design | `superpowers/specs/2026-06-15-atp-platform-grouping-design.md` |

## Two-read orientation

1. Read `CLAUDE.md` (root) — commands, strict layer rules, hard constraints.
2. Read `SERVICES.md` — all protocol signatures and how to inject mocks.

After those two an agent can navigate any feature without guessing.

## Doc inventory

```
docs/
├── README.md                                      ← you are here
├── PRD.md                                         ← product requirements (anchor)
├── ARCHITECTURE.md                                ← layers, module layout, DI overview
├── SERVICES.md                                    ← protocol signatures + DI pattern
├── CODEBASE_RULES.md                              ← folder, size, forbidden/required rules
├── DATA_SOURCES.md                                ← ATP, GTFS, AVL contract details
├── MVP_CHECKLIST.md                               ← phased build plan (14 phases)
├── GTFS_AUTO_UPDATE_PLAN.md                       ← GTFS update pipeline spec
├── FEATURE_ROADMAP.md                             ← comprehensive feature checklist
├── APP_AUDIT_FEATURE_CHECKLIST_2026-06-20.md      ← open audit items (P0/P1/P2)
└── superpowers/specs/                             ← feature design docs
    ├── 2026-06-13-ui-overhaul-design.md
    ├── 2026-06-15-atp-platform-grouping-design.md
    └── 2026-06-20-app-audit-rollout-design.md
```

## What this app is

Native SwiftUI iOS app for Luxembourg public transport. Apple Maps-style
full-screen MapKit map with a persistent draggable bottom sheet. Data from
three live feeds: ATP (mobiliteit.lu OpenAPI), GTFS (local feed), and AVL
(Ville de Luxembourg disruption XML). No backend of our own.
