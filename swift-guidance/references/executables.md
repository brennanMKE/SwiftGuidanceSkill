# Swift Executables and Entry Points

This document covers best practices for Swift executable targets, including entry point definition, file naming, and common patterns.

---

## Rule 1: Never Name the Source File `main.swift`

**This is the most important rule.**

In Swift, the `@main` attribute designates the entry point for an executable. The compiler looks for exactly one `@main` annotation across the entire build.

If you name your entry point file `main.swift`, the compiler generates an implicit `main` function, which conflicts with any explicit `@main` annotation.

### The Problem

```swift
// ❌ File: main.swift
@main
struct MyApp {
    static func main() {
        print("Hello")
    }
}
```

**Result:** Compilation error — implicit `main` from `main.swift` naming conflicts with explicit `@main`.

### The Solution

Choose a descriptive name for your entry point file:

```swift
// ✅ File: App.swift (or MyApp.swift, AppEntry.swift, etc.)
@main
struct MyApp {
    static func main() {
        print("Hello")
    }
}
```

Or structure your project with a separate module and let the compiler find `@main` automatically.

### Why This Matters

- The filename `main.swift` has special meaning in Swift—it creates an implicit entry point
- Explicit `@main` is clearer and more flexible than relying on file naming conventions
- Mixing them causes immediate compilation failure

---

## Entry Point Patterns

### Pattern 1: Single `@main` Struct

Use a simple struct with a static `main()` method:

```swift
// App.swift
import Foundation

@main
struct MyApp {
    static func main() {
        print("Application started")
        // Perform setup and run
        runApplication()
    }
    
    static func runApplication() {
        // Main application logic
    }
}
```

**Best for:** Simple command-line tools, single-entry-point executables.

### Pattern 2: `@main` with Async Entry Point

For applications using Swift Concurrency:

```swift
// App.swift
import Foundation

@main
struct AsyncApp {
    static func main() async {
        await runApplication()
    }
    
    static func runApplication() async {
        let result = try await performWork()
        print("Completed: \(result)")
    }
}
```

**Best for:** Async/await based executables, networking apps, modern concurrency patterns.

### Pattern 3: Multiple Entry Points with Subcommands

Use an enum or a structured approach for CLI tools with multiple commands:

```swift
// App.swift
import Foundation

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
    
    static func buildCommand() {
        print("Building...")
    }
    
    static func testCommand() {
        print("Testing...")
    }
    
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

**Best for:** CLI tools with multiple subcommands.

---

## Compiler-Generated vs. Explicit `@main`

### Implicit Entry Point (Implicit `main`)

If no `@main` annotation exists and no file is named `main.swift`, the compiler generates a default entry point that does nothing.

```swift
// ❌ No @main, no main.swift
// Compiler generates an empty main() automatically
// Application starts but does nothing
```

### Explicit Entry Point (Explicit `@main`)

Using `@main` is always clearer:

```swift
// ✅ Explicit and clear
@main
struct MyApp {
    static func main() {
        print("Starting application")
    }
}
```

**Prefer explicit `@main` for clarity and control.**

---

## File Organization Best Practices

For larger executables, organize code into logical modules:

```
MyApp/
  Sources/
    App.swift              # Contains @main entry point
    Commands/
      BuildCommand.swift
      TestCommand.swift
    Utilities/
      Logger.swift
      FileHelper.swift
```

**Keep the entry point file (`App.swift`) focused on orchestration, not implementation details.**

---

## Accessing Command-Line Arguments

Swift provides `CommandLine.arguments` for parsing input:

```swift
import Foundation

@main
struct CLIApp {
    static func main() {
        let args = CommandLine.arguments
        
        // args[0] is the executable name
        // args[1...] are the provided arguments
        
        if args.count > 1 {
            let command = args[1]
            print("Running command: \(command)")
        } else {
            print("No arguments provided")
        }
    }
}
```

For more complex parsing, consider using the `ArgumentParser` library (part of the Swift Package Manager ecosystem).

---

## Exit Codes

Always exit with appropriate status codes:

```swift
import Foundation

@main
struct CLIApp {
    static func main() {
        do {
            try runApplication()
            exit(0)  // Success
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)  // Failure
        }
    }
    
    static func runApplication() throws {
        // Implementation
    }
}
```

**Standard conventions:**
- `0` — Success
- `1` — General error
- `2` — Misuse of shell command syntax
- Other codes — Application-specific errors

---

## Testing Executables

For testable executables, separate logic from the `@main` entry point:

```swift
// App.swift
import Foundation

@main
struct MyApp {
    static func main() {
        let app = Application()
        app.run()
    }
}

// Application.swift
struct Application {
    func run() {
        // Testable logic here
    }
}

// ApplicationTests.swift
import XCTest

final class ApplicationTests: XCTestCase {
    func testApplicationLogic() {
        let app = Application()
        // Test without relying on @main
    }
}
```

**Best practice:** Keep the `@main` method thin, and move testable logic into separate types.

---

## Common Mistakes

### ❌ Mistake 1: Naming the entry point file `main.swift`

```swift
// main.swift — DO NOT USE THIS NAME
@main
struct App {
    static func main() { }
}
```

**Fix:** Rename to `App.swift` or another descriptive name.

### ❌ Mistake 2: Multiple `@main` Annotations

```swift
// App.swift
@main
struct AppEntry { }

// Other.swift
@main
struct OtherEntry { }
```

**Fix:** Use exactly one `@main` annotation per executable.

### ❌ Mistake 3: Forgetting to Handle Errors

```swift
// ❌ Silent failure
@main
struct App {
    static func main() {
        try? performWork()  // Errors are silently ignored
    }
}
```

**Fix:** Properly handle and report errors:

```swift
// ✅ Explicit error handling
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

When reviewing executable entry points:

- [ ] Entry point file is NOT named `main.swift`
- [ ] Exactly one `@main` annotation per executable
- [ ] `main()` method is static
- [ ] Entry point is concise and delegates to other functions/types
- [ ] Errors are handled with appropriate exit codes
- [ ] Command-line arguments are parsed correctly (or validated)
- [ ] Testable logic is separated from `@main`
- [ ] Exit codes follow standard conventions (0 = success, 1+ = failure)

---

## Summary

1. **Never name the entry point file `main.swift`** — it conflicts with `@main`
2. **Use `@main` explicitly** — it's clearer than implicit entry points
3. **Keep `main()` simple** — delegate to other functions
4. **Handle errors properly** — use appropriate exit codes
5. **Test without `@main`** — separate testable logic
