---
description: Run the full Verkéier test suite
---

Run the full Swift Testing suite and summarize failures (file:line + reason).

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' test
```
