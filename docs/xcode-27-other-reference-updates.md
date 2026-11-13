# Dark Mode, Logging, Multiplatform, Performance & Language Reference Updates for Xcode 27

These references were re-validated in November 2026 against Xcode 27.2
(Swift 6.4.2, macOS 27.2). Each claim was checked against Apple docs or Swift
Evolution, the Xcode 27 templates and build-setting specs, and compiled or
running code. See `xcode-27-swiftui-updates.md` and
`xcode-27-concurrency-updates.md` for the earlier rounds.

---

## Dark mode (`dark-mode.md`)

| Old claim | Correction | Evidence |
|---|---|---|
| With `preferredColorScheme`, "the last value set anywhere in the tree wins" | An outer modifier overrides inner ones **even when its value is `nil`**; among siblings with no overriding ancestor, the **first non-nil** preference in view order wins | Runtime (macOS 27, Dark Mode host): A `.light` + B `.dark` → light; reversed → dark; outer `.light` beat inner `.dark`; outer `nil` + inner `.light`/`.dark` → followed the OS. Apple: "prioritize the first non-nil preference based on the order of the views." The outer-`nil` case was found by the iteration-2 evals and wasn't in the first correction. |
| `Color(.systemBackground)` doesn't compile on macOS or visionOS | It compiles on iOS and **visionOS**. It fails on **macOS** and **tvOS** | Typechecked against each SDK |

**Confirmed:**
- `.environment(\.colorScheme, …)` is scoped to its subtree.
- `Color(light:dark:)` is not in any 27.2 SDK.
- All other samples compile on macOS, iOS, visionOS and tvOS.

## Logging (`logging.md`, rewritten)

| Old claim | Correction | Evidence |
|---|---|---|
| Values are redacted "in release builds" | Redaction depends on whether a debugger is attached, not on the build configuration | An unoptimized build without a debugger showed `<private>` |
| "numbers, dates always safe" | `Int`/`Double`/`Bool` are shown. `String`, `Date` and custom types are `<private>` | `log show` output |
| Debug/Info "visible in debug builds", Warning+ "in release" | Levels control storage: debug and info stay in memory only, notice and above are persisted. `log show` needs `--info --debug` to show the lower levels | Apple docs table, CLI |
| Warning listed as its own level | `warning` is stored at the **error** level and `critical` at the **fault** level | `messageType` in `log show` |
| `log stream --follow` | Not a valid option. `log stream` already follows | `unrecognized option '--follow'` |
| Signpost sample using `Logger` | Didn't compile (`OSSignpostID(log:)` takes an `OSLog`). Replaced with `OSSignposter` | Compiler |
| Loggers must be `nonisolated` | Optional; a global `Logger` (`Sendable`) is usable from any isolation | Compiler |

Added: `.private(mask: .hash)`, verified to log `<mask.hash: '…'>`.

## Multiplatform (`multiplatform.md`)

- Replaced `SDKROOT[sdk=iphone*] = iphoneos` with what Xcode 27's multiplatform
  template uses: `SDKROOT = auto` plus `SUPPORTED_PLATFORMS`.
- Added per-SDK `LD_RUNPATH_SEARCH_PATHS`.
- Noted that an `[sdk=…]` condition on `SDKROOT` itself is circular. This is
  not verified at runtime, because the test target type couldn't build for iOS.

## Performance (`performance.md`)

- **Wrong migration:** replacing `DispatchQueue.global().async` with
  `Task { await expensiveComputation() }` from the main actor runs the work **on
  the main thread** under Approachable Concurrency. The fix is to mark the
  CPU-bound function `@concurrent`.
- **Missing caveat:** the cooperative pool is sized to the core count, so never
  block inside a task.
- **Checklist:** `NSLock` → actor *or* `Mutex`. `DispatchWorkItem.cancel()` exists.

## Executables (`executables.md`, rewritten)

| Old claim | Correction | Evidence |
|---|---|---|
| "Never name the file `main.swift`" as the most important rule; `@main` in `main.swift` always fails | The real rule is one entry point per module: no `@main` inside `main.swift`, and no mixing it with top-level code. It fails with `swiftc` and in Xcode, but **SwiftPM 6.x builds it**, because it passes `-parse-as-library`. Xcode's Command Line Tool template generates `main.swift` with top-level code | `swift build` ran it; `swiftc` gave `'main' attribute cannot be used in a module that contains top-level code` |
| No `@main` and no `main.swift` → an empty `main` that does nothing | The link fails: `Undefined symbols … "_main"` | Linker |
| "exactly one `@main` across the entire build" | One per **module** | `'main' attribute can only apply to one type in a module` |
| Async sample, duplicate-`@main` sample, error-handling sample | Didn't compile (`try` in a non-throwing function, missing `main()`, missing `import Foundation`). Fixed | Compiler |
| Prefer `@main` over implicit entry points | Both are supported. Top-level `await` in `main.swift` has worked since 5.7 | SE-0343 |
| ArgumentParser is "part of SwiftPM" | It's a separate package. Validation errors exit with 64 (`EX_USAGE`) | Package docs |

## Transitive dependencies (`transitive-dependencies.md`, rewritten)

| Old claim | Correction | Evidence |
|---|---|---|
| Both features are "opt-in as of Swift 6.2" | Both are still upcoming in 6.4 (slated for Swift 7 mode), but **Xcode 27 new-project templates turn on `MemberImportVisibility`** | `-print-supported-features`; template plist |
| `internal import` means clients don't load the dependency | Only for **library-evolution** modules. Non-resilient clients still load it | `-Rmodule-loading`; SE-0409 |
| SE-0444 covers operators, conformances and macros | It covers extension members (methods, properties, subscripts, initializers, nested types). Conformances and operators are future directions; macros always needed a direct import | Compile tests; SE-0444 |
| Error message wording | Updated to the real diagnostics (`… is not available due to missing import of defining module …`, `function cannot be declared public because its result uses an internal type`) | Compiler |
| `@_implementationOnly` prevents runtime loading | Neither attribute affects runtime loading. `@_implementationOnly` is unsafe in non-resilient modules, and 6.4 warns `[#ImplementationOnlyDeprecated]` | SE-0409; compiler |
| Enable in Xcode via `OTHER_SWIFT_FLAGS`; `InternalImportsByDefault` first | Use the dedicated build settings (`MEMBER_IMPORT_VISIBILITY` supports `MIGRATE`). Start with `MemberImportVisibility` (`swift package migrate --to-feature MemberImportVisibility`) | `Swift.xcspec` |
| `AccessLevelOnImport` was an upcoming feature in 5.9–5.10 | It was experimental. The syntax works in all language modes in 6.x | SE-0409 |

## Implicit return (`implicit-return.md`)

These were small fixes; 22 of the 23 samples compiled.

- **Accepted branches:** a branch may `throw` or call `fatalError()`.
- **Branch types:** they need to *convert* to the contextual type, not match exactly.
- **Missing rules, now added:**
  - an `if` expression needs an `else`;
  - it can't be part of a larger expression;
  - each branch must be a single expression.
- **Labels and imports:** the "Not valid" heading is now "Not a candidate", and the sample that was missing `import Foundation` now has it.
- **Sources:** SE-0255 (5.1) and SE-0380 (5.9) are cited.
