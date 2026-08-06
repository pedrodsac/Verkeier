---
description: Run a single test class or method, e.g. /test-one GTFSValidatorTests
argument-hint: <TestClass[/testMethod]>
---

Run only the test target `$ARGUMENTS` and summarize the result.

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:VerkéierTests/$ARGUMENTS
```
