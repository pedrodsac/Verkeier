---
description: Run the full LuxTransit test suite
---

Run the full Swift Testing suite and summarize failures (file:line + reason).

```sh
xcodebuild -project LuxTransit.xcodeproj -scheme LuxTransit -destination 'platform=iOS Simulator,name=iPhone 17' test
```
