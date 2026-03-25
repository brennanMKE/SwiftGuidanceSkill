# Unified Logging with os.log

Use Apple's [unified logging system](https://developer.apple.com/documentation/os/logging) (`os.log`) for structured, privacy-aware output. Logs appear in **Console.app**, `log` CLI, and are automatically captured in crash reports.

---

## Setup

Create a shared logging configuration:

```swift
// Logging.swift
import Foundation

enum Logging {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.app"
}
```

Each file declares a **file-scoped, nonisolated logger** at the top:

```swift
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "DataStore")
```

**Why `nonisolated`:**
- `Logger` is a value type and safe to create from any thread
- Avoids spurious `@MainActor` warnings in MainActor-by-default projects
- Creates the logger once per file, not on each access

**Why `private`:**
- Scopes logger to the file
- Prevents logger leaks across modules

**Why `category`:**
- Identifies the subsystem/feature in Console.app (e.g., `"NetworkService"`, `"DataParser"`)
- Allows filtering logs by source

---

## Log Levels

Use the appropriate level for the situation:

| Level | Method | When to use |
|-------|--------|-------------|
| **Debug** | `logger.debug(...)` | Verbose tracing: method entry/exit, variable values, state transitions |
| **Info** | `logger.info(...)` | Informational: significant but expected events (startup, user actions) |
| **Notice** | `logger.notice(...)` | Default level; important events (important milestones) |
| **Warning** | `logger.warning(...)` | Unexpected but recoverable situations |
| **Error** | `logger.error(...)` | Errors that affect functionality |
| **Fault** | `logger.fault(...)` | Programming errors, assertions, unrecoverable failures |

---

## Examples

```swift
// Entry/exit tracing
logger.debug("Entering fetchUsers()")

// Significant event
logger.info("Network request started for URL: \(url)")

// Parameter values
logger.debug("Processing item: id=\(item.id) count=\(items.count)")

// Warning about unexpected state
logger.warning("Retry attempt \(attempts)/\(maxRetries)")

// Error with context
logger.error("Failed to parse JSON: \(error)")

// Fault for programming errors
logger.fault("Invariant violated: state should not be nil")
```

---

## Privacy in Release Builds

`os.log` **redacts dynamic values in release builds by default**. To show a value in release logs:

```swift
// ❌ REDACTED in release (shows "<redacted>")
logger.debug("User name: \(user.name)")

// ✅ VISIBLE in release
logger.debug("User name: \(user.name, privacy: .public)")

// ✅ EXPLICITLY REDACTED (for clarity)
logger.debug("API key: \(apiKey, privacy: .private)")

// ✅ For non-string values (numbers, dates always safe)
logger.debug("User ID: \(user.id) Request count: \(count)")
```

**Guidelines:**
- Keep sensitive data (passwords, tokens, PII) at default (redacted)
- Use `.public` for non-sensitive values needed in production debugging
- Debug/Info logs are visible in debug builds; Warning/Error/Fault are visible in release

---

## Viewing Logs

### Console.app (Visual)

1. Open Console.app → select your device
2. Filter by subsystem: enter your app's bundle identifier
3. Click the category filter icon to filter by category
4. Search by text: `Command+F`

### Command Line

```bash
# All logs from your app
log stream --predicate 'subsystem == "com.example.app"' --level debug

# From a specific category
log stream --predicate 'subsystem == "com.example.app" and category == "DataStore"' --level debug

# Real-time monitoring
log stream --predicate 'subsystem == "com.example.app"' --follow --level debug

# Show logs from last 10 minutes
log show --last 10m --predicate 'subsystem == "com.example.app"'

# Export to file
log show --last 1h --predicate 'subsystem == "com.example.app"' > app-logs.txt
```

### Filtering in Console.app

- **Exclude:** Drag a log entry to the Exclude section
- **Include:** Right-click → "Add to Filter"
- **Composite:** Combine multiple filters with AND/OR logic

---

## Signposts for Performance Analysis

Use signposts to measure operation timing in Instruments:

```swift
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "Performance")

func expensiveOperation() {
    let signpostID = OSSignpostID(log: logger)
    os.signpost(.begin, log: logger, name: "DataFetch", signpostID: signpostID)

    // Perform work
    let data = fetchData()

    os.signpost(.end, log: logger, name: "DataFetch", signpostID: signpostID)
}
```

Signposts appear in Instruments (Time Profiler, System Trace) and can be correlated with other system activity.

---

## Best Practices

1. **Use categories consistently** — Same file = same category
2. **Log at appropriate levels** — Don't spam debug logs
3. **Include context** — Log what's happening, not just that it happened
4. **Avoid logging sensitive data** — Or use `.private` explicitly
5. **Keep loggers file-scoped** — Don't share loggers across files
6. **Use `nonisolated private let`** — Avoids isolation warnings
7. **Log errors with context** — Include the error and why it matters

---

## Migration from print() and NSLog()

```swift
// ❌ OLD
print("User fetched: \(user)")
NSLog("Error: %@", error.localizedDescription)

// ✅ NEW
import os.log
nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "Users")
logger.info("User fetched: \(user)")
logger.error("Error: \(error.localizedDescription)")
```

Unified logging is superior:
- Structured and searchable
- Privacy-aware (redacts in release)
- Automatically captured in crash reports
- Integrates with Instruments
- Lower overhead than print()
