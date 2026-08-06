# Codebase Rules

This must be treated as a serious maintainable iOS project, not a throwaway prototype.

## Folder Structure

Use clear folders by feature and layer.

Do not dump files into the root project folder.

Preferred structure:

```text
Features/<FeatureName>/Views
Features/<FeatureName>/ViewModels
Features/<FeatureName>/Components
Services/<ServiceName>
Models
Storage
Networking
Utilities
Resources
Tests
```

## File Size

Guidelines:

- most Swift files should stay under 300–400 lines
- split large views into smaller subviews
- split large services into client, decoder, mapper, mock, and fixtures
- do not create files with thousands of lines
- if a file grows in multiple directions, refactor before continuing

## Forbidden

Do not:

- put the whole app in `ContentView.swift`
- put networking inside SwiftUI views
- put business logic inside view bodies
- create god objects
- hardcode API keys
- hardcode fake data as production data
- remove attribution/legal screens
- claim the app is official
- add accounts, ads, subscriptions, or backend unless explicitly requested

## Required

Do:

- use dependency injection where useful
- provide mock services for previews/tests
- use typed models
- use async/await
- handle loading, empty, error, stale, and offline states
- add TODO comments where external API assumptions are uncertain
- keep UI native, clean, and Apple-like
- support Dynamic Type and VoiceOver
- build after each phase

## AI Agent Guidance

When working in this codebase as an AI agent:

- Start with `docs/README.md` to orient yourself, then read `docs/SERVICES.md`
  for service contracts before touching any feature code.
- Never guess a protocol method signature — read the protocol file directly
  (`Verkéier/Services/<Name>/<Name>.swift`).
- Inject mocks via `.environment(\.serviceName, MockImpl())` in previews;
  pass mock implementations directly to view model constructors in tests.
- `DataSource.mock` must never appear in production code paths — it is
  strictly for fixtures and `#Preview` blocks.
