# Unified Logging with os.log

Use Apple's [unified logging system](https://developer.apple.com/documentation/os/logging) (`Logger` from the `os` module) for structured, privacy-aware output. Logs appear in **Console.app**, the `log` CLI, and sysdiagnoses.

Behavior below was verified on macOS 27 (Xcode 27.2) by logging from a test binary and reading the result with `log show`.

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

Each file declares a **file-scoped logger** at the top:

```swift
import os

private let logger = Logger(subsystem: Logging.subsystem, category: "DataStore")
```

**Why file-scoped `let`:**
- Created once (globals initialize lazily), not on every access
- `Logger` is `Sendable`, so the global is usable from any isolation — including
  actors and nonisolated code in MainActor-by-default projects. Marking it
  `nonisolated private let` is optional (documents intent); don't flag its absence.

**Why `private`:** scopes the logger to the file.

**Why `category`:** identifies the feature in Console.app (e.g. `"NetworkService"`,
`"DataParser"`) and allows filtering by source.

---

## Log Levels

Levels control **how messages are stored**, not whether they appear in debug vs
release builds:

| Level | Method | Stored | When to use |
|-------|--------|--------|-------------|
| Debug | `logger.debug(...)` | memory only; not persisted | Verbose tracing during development |
| Info | `logger.info(...)` | memory only, unless the `log` tool configures persistence | Helpful but non-essential detail |
| Notice (default) | `logger.notice(...)` / `logger.log(...)` | persisted to disk (up to a storage limit) | Essential events for troubleshooting |
| Error | `logger.error(...)` | persisted | Errors that affect functionality |
| Fault | `logger.fault(...)` | persisted, with extra process context | Bugs and invariant violations |

`logger.warning(...)` and `logger.critical(...)` are aliases: `warning` logs at
the **error** level and `critical` at the **fault** level (verified: a
`warning` message is stored with type `Error`).

`log show` omits debug and info messages unless you pass `--info --debug`.

---

## Examples

```swift
logger.debug("Entering fetchUsers()")
logger.info("Request started: \(url, privacy: .public)")
logger.debug("Processing item id=\(item.id) count=\(items.count)")
logger.error("Retry \(attempts)/\(maxRetries) failed")
logger.error("Failed to parse JSON: \(error.localizedDescription, privacy: .public)")
logger.fault("Invariant violated: state should not be nil")
```

---

## Privacy

Interpolated values are redacted as `<private>` **unless the process is being
debugged** — this is not a debug-vs-release build distinction (verified: an
unoptimized build run without a debugger showed `<private>`). Apple: "By default,
the system doesn't redact integer, floating-point and Boolean values, but it does
redact the contents of dynamic strings and complex dynamic objects."

Verified defaults:

| Interpolated value | Shown by default |
|---|---|
| `Int`, `Double`, `Bool` | yes |
| `String` | `<private>` |
| `Date` | `<private>` |
| Custom types (`CustomStringConvertible`) | `<private>` |

```swift
logger.notice("User name: \(user.name)")                     // <private>
logger.notice("Screen: \(screenName, privacy: .public)")      // visible
logger.notice("Token: \(token, privacy: .private)")           // explicitly redacted
logger.notice("Email hash: \(email, privacy: .private(mask: .hash))") // correlatable, not readable
logger.notice("Count: \(count)")                              // visible (integer)
```

**Guidelines:**
- Leave sensitive data (passwords, tokens, PII) at the default or mark it `.private`
- Mark non-sensitive strings `.public` when you need them in field logs
- Use `.private(mask: .hash)` to correlate values across messages without exposing them
- Don't rely on default visibility for types other than integers, floats, and booleans — mark them explicitly

---

## Viewing Logs

### Console.app

1. Open Console.app → select the device
2. Click **Start Streaming** (or use **Action → Include Info/Debug Messages** to see lower levels)
3. Filter by subsystem (your bundle identifier) and category

### Command Line

zsh has a built-in `log` command; use `/usr/bin/log` in scripts if `log` misbehaves.

```bash
# Live stream (log stream follows by default)
log stream --predicate 'subsystem == "com.example.app"' --level debug

# A specific category
log stream --predicate 'subsystem == "com.example.app" and category == "DataStore"' --level debug

# Stored logs from the last 10 minutes (add --info --debug for lower levels)
log show --last 10m --info --debug --predicate 'subsystem == "com.example.app"'

# Export
log show --last 1h --predicate 'subsystem == "com.example.app"' > app-logs.txt
```

---

## Signposts for Performance Analysis

Use `OSSignposter` (iOS 15 / macOS 12+) to measure intervals in Instruments.
The older `os_signpost` / `OSSignpostID(log:)` APIs take an `OSLog`, not a `Logger`.

```swift
import os

private let signposter = OSSignposter(subsystem: Logging.subsystem, category: "Performance")

func expensiveOperation() {
    let state = signposter.beginInterval("DataFetch")
    defer { signposter.endInterval("DataFetch", state) }

    let data = fetchData()
    ...
}

// Or wrap a closure
let data = signposter.withIntervalSignpost("DataFetch") { fetchData() }
```

Intervals appear in Instruments' os_signpost track for your subsystem. To show them in the **Points of Interest** track, create the signposter with the `.pointsOfInterest` category: `OSSignposter(subsystem: Logging.subsystem, category: .pointsOfInterest)`.

---

## Best Practices

1. **Use categories consistently** — one category per file or component
2. **Pick levels by importance** — debug for tracing, notice and above for what you need in the field
3. **Include context** — what happened and why it matters
4. **Mark privacy explicitly** for anything other than numbers and booleans
5. **Keep loggers file-scoped** — `private let logger = Logger(...)`

---

## Code Review Checklist

- [ ] Uses `Logger` — no `print()` or `NSLog()` in production code
- [ ] File-scoped `private let` loggers with a consistent subsystem
- [ ] Categories reflect the file or component
- [ ] Levels match importance (debug/info aren't persisted; notice+ are)
- [ ] Sensitive values default-redacted or `.private`; needed non-sensitive strings marked `.public`
- [ ] Errors logged with context
- [ ] Signposts use `OSSignposter`
