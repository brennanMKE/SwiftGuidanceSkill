# Swift Executables and Entry Points

Best practices for Swift executable targets: entry points, file naming, and
common patterns. Behavior verified with Swift 6.4.2 / Xcode 27.2 using plain
`swiftc` and SwiftPM.

---

## Rule 1: Don't Put `@main` in `main.swift`

A module has exactly **one** entry point — either top-level code in
`main.swift`, or a single `@main` type. Don't mix them.

The compiler treats `main.swift` as top-level code, which generates the entry
point implicitly. Adding `@main` inside it (or anywhere else in a module that
also has top-level code in `main.swift`) fails:

```swift
// ❌ File: main.swift
@main
struct MyApp {
    static func main() {
        print("Hello")
    }
}
```

```
error: 'main' attribute cannot be used in a module that contains top-level code
```

**Build-system caveat:** SwiftPM 6.x compiles executable targets with
`-parse-as-library`, so this exact file *does* build and run under `swift build`
(verified). It fails with plain `swiftc` and in Xcode targets. Don't rely on the
SwiftPM behavior — code that only builds in one system is fragile.

### The Solution

Pick one style.

```swift
// ✅ @main in a file named after the type: MyApp.swift (or App.swift, CLI.swift)
@main
struct MyApp {
    static func main() {
        print("Hello")
    }
}
```

```swift
// ✅ main.swift with top-level code (what Xcode's Command Line Tool template generates)
print("Hello")
let result = await fetchSomething()   // top-level await works since Swift 5.7 (SE-0343)
```

Top-level code in `main.swift` is `@MainActor`-isolated, like a synchronous
`@main` `main()`.

**Review rule:** flag only `@main` inside `main.swift`, or `@main` plus
top-level code elsewhere in `main.swift`. A `main.swift` with top-level code
and no `@main` is fine.

Note: compiling a **single** file with plain `swiftc` treats that file as the
main file even if it isn't named `main.swift`, so a lone `@main` file needs
`swiftc -parse-as-library`. Xcode and SwiftPM pass `-parse-as-library`
automatically when the target has no `main.swift` (verified: a single-file
Xcode 27 command-line target with `@main` in `ImageTool.swift` builds and runs
with no extra flags) — don't add it to `OTHER_SWIFT_FLAGS`.

---

## Entry Point Patterns

### Pattern 1: Single `@main` Struct

```swift
// MyApp.swift
@main
struct MyApp {
    static func main() {
        print("Application started")
        runApplication()
    }

    static func runApplication() {
        // Main application logic
    }
}
```

**Best for:** Simple command-line tools.

### Pattern 2: Async (and throwing) Entry Point

`main()` may be `async`, `throws`, or both. An uncaught error from a throwing
`main()` terminates the process with a non-zero status.

```swift
// MyApp.swift
@main
struct AsyncApp {
    static func main() async throws {
        let result = try await performWork()
        print("Completed: \(result)")
    }

    static func performWork() async throws -> Int {
        42
    }
}
```

**Best for:** Executables that use async/await.

### Pattern 3: Subcommands

```swift
// CLI.swift
@main
struct CLI {
    static func main() {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            printUsage()
            return
        }

        switch arguments[1] {
        case "build":
            buildCommand()
        case "test":
            testCommand()
        case "help":
            printUsage()
        default:
            print("Unknown command: \(arguments[1])")
            printUsage()
        }
    }

    static func buildCommand() { print("Building...") }
    static func testCommand() { print("Testing...") }

    static func printUsage() {
        print("""
        Usage: cli <command>
        Commands:
          build - Build the project
          test  - Run tests
          help  - Show this message
        """)
    }
}
```

For anything beyond a few subcommands, use
[swift-argument-parser](https://github.com/apple/swift-argument-parser) — a
separate package you add as a dependency
(`.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")`),
with `@main struct Tool: ParsableCommand` or `AsyncParsableCommand`.

---

## No Entry Point at All

If a module has neither `@main` nor `main.swift`, there is no entry point and
the **link fails**:

```
Undefined symbols for architecture arm64: "_main"
```

---

## Choosing a Style

Both styles are fully supported. Prefer one consistently per project:

- **`@main`** when the entry type should be named, or `main()` should be
  `async throws` with a clear signature; also required for SwiftUI/AppKit/UIKit
  `App`/delegate entry points
- **`main.swift`** for short scripts and tools; it's what Xcode's Command Line
  Tool template generates

---

## File Organization

SwiftPM expects sources under `Sources/<TargetName>/` (unless the target sets `path:`):

```
MyTool/
  Package.swift
  Sources/
    MyTool/
      MyTool.swift          # @main entry point
      Commands/
        BuildCommand.swift
      Utilities/
        FileHelper.swift
```

Keep the entry point focused on orchestration, not implementation details.

---

## Command-Line Arguments

```swift
@main
struct CLIApp {
    static func main() {
        let args = CommandLine.arguments
        // args[0] is the executable path; args[1...] are the arguments

        if args.count > 1 {
            print("Running command: \(args[1])")
        } else {
            print("No arguments provided")
        }
    }
}
```

---

## Exit Codes

Returning normally from `main()` exits with status `0`. Exit non-zero on failure:

```swift
import Foundation

@main
struct CLIApp {
    static func main() {
        do {
            try runApplication()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runApplication() throws {
        // Implementation
    }
}
```

**Conventions:**
- `0` — success
- `1` — general error
- `2` — shell builtin misuse (shell convention); `64` (`EX_USAGE`) — command-line usage error (sysexits; what ArgumentParser uses for validation errors)
- other — application-specific

---

## Testing Executables

Keep `@main` thin and move logic into types that tests can reach.
`@testable import` of an executable target works in SwiftPM test targets.

```swift
// MyApp.swift
@main
struct MyApp {
    static func main() {
        Application().run()
    }
}

// Application.swift
struct Application {
    func run() {
        // Testable logic here
    }
}

// Tests/MyAppTests/ApplicationTests.swift
import Testing
@testable import MyApp

@Test func applicationRuns() {
    Application().run()
}
```

---

## Common Mistakes

### ❌ Mistake 1: `@main` inside `main.swift`

```swift
// main.swift
@main
struct App {
    static func main() { }
}
```

**Fix:** rename the file (e.g. `App.swift`), or remove `@main` and use top-level code.

### ❌ Mistake 2: Multiple `@main` types in one module

```swift
// App.swift
@main
struct AppEntry {
    static func main() { }
}

// Other.swift
@main
struct OtherEntry {
    static func main() { }
}
```

Fails with `'main' attribute can only apply to one type in a module` (or a
`duplicate symbol '_main'` link error in non-whole-module builds).

**Fix:** exactly one `@main` per module.

### ❌ Mistake 3: Swallowing errors

```swift
// ❌ Silent failure
@main
struct App {
    static func main() {
        try? performWork()
    }
}
```

```swift
// ✅ Report and exit non-zero
import Foundation

@main
struct App {
    static func main() {
        do {
            try performWork()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }
}
```

---

## Code Review Checklist

- [ ] No `@main` inside `main.swift`; no mix of top-level code and `@main`
- [ ] Exactly one `@main` type per module
- [ ] `main()` is `static` (may be `async` / `throws`)
- [ ] Entry point is thin and delegates to other types
- [ ] Errors are reported and produce a non-zero exit status
- [ ] Command-line arguments are validated (ArgumentParser for non-trivial CLIs)
- [ ] Testable logic is separated from the entry point

---

## Summary

1. **One entry point per module** — `@main` type *or* `main.swift` top-level code, never both
2. **Don't put `@main` in `main.swift`** — it fails outside SwiftPM
3. **Keep `main()` thin** — delegate to other types
4. **Exit non-zero on failure**
5. **Test the logic, not the entry point**
