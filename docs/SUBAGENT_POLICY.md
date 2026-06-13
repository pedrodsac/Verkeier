# Subagent Policy

GPT-5.5 is the lead architect and final reviewer.

Use subagents deliberately. Do not delegate architecture blindly.

## Use GPT-5.4 for

- architecture decisions
- bottom sheet interaction design
- MapKit integration
- ActivityKit / Live Activities
- App Intents architecture
- GTFS data modelling
- ATP response normalization
- caching strategy
- concurrency design
- hard debugging
- large refactors
- release/privacy/legal checks

## Use GPT-5.4 mini for

- simple Swift files
- boilerplate SwiftUI views
- small model structs
- mock data
- simple unit tests
- preview fixtures
- localization scaffolding
- basic JSON/XML parser helpers
- formatting cleanup
- README/doc updates

## Subagent Rules

Subagents must not:

- change architecture without review
- add backend
- add accounts, subscriptions, or ads
- remove attribution
- hardcode API keys
- create giant files
- overbuild beyond MVP
- fake live data as real data
- claim the app is official

GPT-5.5 must review subagent code before accepting it.
