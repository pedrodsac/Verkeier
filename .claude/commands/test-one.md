---
description: Run a single test class or method, e.g. /test-one GTFSValidatorTests
argument-hint: <TestClass[/testMethod]>
---

Run only the test target `$ARGUMENTS` and summarize the result.

```sh
xcodebuild -project LuxTransit.xcodeproj -scheme LuxTransit -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LuxTransitTests/$ARGUMENTS
```
