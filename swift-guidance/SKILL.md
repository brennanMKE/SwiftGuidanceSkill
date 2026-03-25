---
name: swift-guidance
description: Provide guidance for working with Swift and Xcode, including concurrency, logging, performance, and UI best practices.
license: MIT
metadata:
  author: Brennan Stehling
  version: "1.0"
---

Review Swift code for correctness, modern API usage, and adherence to best practices. Report only genuine problems - do not nitpick or invent issues.

## Guidance Process

1. Check for deprecated concurrency patterns using `references/concurrency.md`.
2. Validate actor isolation and `@MainActor` usage using `references/actor-isolation.md`.
3. Review logging patterns using `references/logging.md`.
4. Check SwiftUI best practices using `references/ui.md`.
5. Ensure performance optimizations using `references/performance.md`.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- Always use Swift Concurrency (async/await) instead of Combine or Dispatch.
- Properly annotate types with `nonisolated` or `@MainActor` in MainActor-by-default projects.
- Use Apple's unified logging system (`os.log`) with file-scoped loggers.
- Use `@Observable` macro instead of `ObservableObject` in SwiftUI.
- Avoid `GeometryReader` — use `onGeometryChange()` instead.
- Prioritize performance and efficient resource usage.

## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated (e.g., "Use Swift Concurrency instead of Dispatch").
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

### Example Output

**ViewController.swift, Line 42: Use Swift Concurrency instead of DispatchQueue**

```swift
// Before
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    self.updateUI()
}

// After
Task {
    try? await Task.sleep(for: .seconds(1))
    updateUI()
}
```

**DataManager.swift, Line 18: Add proper logging at startup**

```swift
// Before
class DataManager {
    init() {
        print("DataManager initialized")
    }
}

// After
import os.log

nonisolated private let logger = Logger(subsystem: "com.app", category: "DataManager")

class DataManager {
    init() {
        logger.info("DataManager initialized")
    }
}
```

### Summary

1. **Concurrency (high):** Replace DispatchQueue with async/await on line 42.
2. **Logging (medium):** Add structured logging on line 18.

End of example.

## References

- `references/concurrency.md` - Modern Swift Concurrency patterns and avoiding deprecated APIs.
- `references/logging.md` - Apple's unified logging system and structured debug output.
- `references/actor-isolation.md` - Proper actor isolation in concurrent code.
- `references/performance.md` - Performance optimization and resource efficiency.
- `references/ui.md` - SwiftUI and AppKit best practices.
