# Swift Concurrency Guidance Updates for Xcode 27

In November 2026 the concurrency references were re-validated against Xcode
27.2 (Swift 6.4.2). Each claim was checked four ways:

1. **Apple documentation and Swift Evolution**: the `Task` and
   `withTaskCancellationHandler` reference pages, and SE-0461.
2. **Xcode build system**: `Swift.xcspec` (which settings map to which
   compiler flags, and under which Swift versions) and the Xcode 27 project
   templates.
3. **A real Xcode project**: a minimal `.xcodeproj` built with `xcodebuild` in
   Swift 5 and Swift 6 modes, checking the `swiftc` flags in the build log and
   the runtime behavior.
4. **Compiled and run code**: test programs built with `swiftc` under each flag
   combination, checking `Thread.isMainThread`, compiler diagnostics, task
   completion, and cancellation ordering.

Files changed:

- `swift-guidance/references/project-configuration.md` (rewritten)
- `swift-guidance/references/nonisolated-concurrent.md` (rewritten)
- `swift-guidance/references/concurrency.md` (rewritten)
- `swift-guidance/references/actor-isolation.md`
- `swift-guidance/references/performance.md` (locking section)
- `swift-guidance/SKILL.md`

---

## New recommended configuration

### Xcode

```
SWIFT_VERSION = 6.0
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

**Xcode 27 app templates** set `SWIFT_APPROACHABLE_CONCURRENCY = YES` and
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, but leave **`SWIFT_VERSION = 5.0`**.
In Swift 5 mode, data-race diagnostics are warnings at most. The skill now
recommends changing it to `6.0`.

`SWIFT_STRICT_CONCURRENCY` was removed from the recommendation. The xcspec
applies it only when the Swift version is 4, 4.2 or 5. In Swift 6 mode it is
ignored, because checking is already complete.

What Approachable Concurrency actually passes to `swiftc` (from the build log):

| `SWIFT_VERSION` | Flags added by `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
|---|---|
| 6.0 | `NonisolatedNonsendingByDefault`, `InferIsolatedConformances` |
| 5.0 | the two above, plus `DisableOutwardActorInference`, `GlobalActorIsolatedTypesUsability`, `InferSendableFromCaptures` |

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` passes `-default-isolation=MainActor`.

### Swift packages

SwiftPM has no Approachable Concurrency setting, so the features must be listed
by name. Tools version 6.0+ already builds in Swift 6 mode, so
`.enableUpcomingFeature("StrictConcurrency")` was dropped as redundant.

```swift
// swift-tools-version: 6.2
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]
```

The old package example, with only `StrictConcurrency` and `.defaultIsolation`,
behaved differently from the Xcode target. The same `nonisolated async`
function ran **off** the main actor in the package and **on** it in Xcode.
With the corrected settings, both run on the main actor.

---

## The central correction: where `nonisolated async` runs

The skill said that in Swift 6+, `nonisolated async` inherits the caller's
actor by default. **That's only true with `NonisolatedNonsendingByDefault`.**
SE-0461 (implemented in Swift 6.2) gates the change behind that upcoming
feature. The Swift 6 language mode does not turn it on.

Measured from a `@MainActor` caller:

| Configuration | `nonisolated async` | `nonisolated(nonsending)` | `@concurrent` |
|---|---|---|---|
| Swift 6 | off main | on main | off main |
| Swift 6 + MainActor default | off main | on main | off main |
| Swift 6 + `NonisolatedNonsendingByDefault` | **on main** | on main | off main |
| Swift 5 + `NonisolatedNonsendingByDefault` | **on main** | — | off main |

The guidance now says to check the build settings before reviewing
`nonisolated async` code. It recommends `@concurrent` and
`nonisolated(nonsending)` as explicit spellings that behave the same in every
configuration. `nonisolated(nonsending)` wasn't mentioned before.

---

## Other corrections

| Old claim | Correction | Evidence |
|---|---|---|
| An actor conforming to a main-actor protocol runs "on MainActor" and "will deadlock" | The actor's method runs on the actor, off main, with access to its state. No deadlock. Unannotated protocol requirements *are* `@MainActor` under default isolation, so nonisolated callers can't use them synchronously. | Runtime + compile error `call to main actor-isolated instance method 'name()' in a synchronous nonisolated context` |
| A `Task` that isn't stored "is immediately deallocated… may be cancelled" | It runs to completion and is not cancelled. Keep the handle only to cancel or await. | Runtime; Apple: "A task runs regardless of whether you keep a reference to it." |
| `@MainActor class UserViewModel: Observable { @ObservationIgnored … }` | Never notifies observers, so SwiftUI won't update. Replaced with `@MainActor @Observable`. | `withObservationTracking` never fired |
| Forgetting `await` "returns Task, not User" | Compile error: `expression is 'async' but is not marked with 'await'` | Compiler |
| `func fetchAndUpdate() async -> User { return try await … }` | Didn't compile (not `throws`); removed | Compiler |
| `onCancel` is "cleanup: called when Task is cancelled" | Runs immediately and at the same time as the operation; runs *before* it if the task was already cancelled. Must be thread-safe. Cleanup belongs in `defer`. | Runtime ordering + Apple docs |
| `Task {}` is fire-and-forget where "structured concurrency ensures cleanup" | `Task {}` is unstructured. Use `async let` or task groups for structured work. | Language semantics |
| Unannotated structs warn wherever they're used off-main | Reading their properties is fine. Their **methods and conformances** are `@MainActor`, so `JSONEncoder().encode` from an actor is an error. | Compile errors |
| Struct `var` fields are "always" `Sendable` | Not when a stored property is a non-`Sendable` class. `public` structs aren't inferred `Sendable`. | Compile errors |
| File-scoped `Logger` must be `nonisolated` | Optional. A `Sendable` global `let` is usable from any isolation. | Compiles clean from an actor and a nonisolated function |
| Use actors instead of locks | Added `Mutex` (Synchronization, iOS 18 / macOS 15) for synchronous access. It's a checked `Sendable`, with no `@unchecked`. | Compiles clean |
| `performance.md` actor example returned `[String: Any]` | `Any` isn't `Sendable`, so it can't cross the actor boundary in Swift 6. Changed to `Data`. | Language semantics |

---

## Confirmed unchanged

- `@concurrent` rules. Each one produced its compile error:
  - `cannot use @concurrent on non-async global function`
  - `multiple actor-isolation attributes (@MainActor and @concurrent)`
  - `actor-isolated property 'value' can not be mutated from a nonisolated context`
- `@concurrent` always leaves the caller's actor.
- `Task {}` created on the main actor runs on the main actor. `Task.detached` doesn't.
- Actors are not given the default main-actor isolation.
- `nonisolated` on protocol requirements, and `nonisolated protocol`, are valid.

---

## Re-running the checks

- **Build-setting mapping**: parse
  `SharedFrameworks/SwiftBuild.framework/.../SWBUniversalPlatform.framework/Versions/A/Resources/Swift.xcspec`
  with `plutil -convert json` and look at the `Condition` and
  `CommandLineArgs` entries.
- **Template defaults**: grep
  `Developer/Library/Xcode/Templates/Project Templates/Base/` for
  `SWIFT_VERSION` and `SWIFT_APPROACHABLE_CONCURRENCY`.
- **Flags reaching `swiftc`**: build a minimal `.xcodeproj` with `xcodebuild`
  from a clean `-derivedDataPath`, then grep the log for
  `-enable-upcoming-feature`, `-default-isolation` and `-swift-version`.
- **Execution context**: call `nonisolated async`, `nonisolated(nonsending)`
  and `@concurrent` functions from `@MainActor`. Read `Thread.isMainThread`
  inside a synchronous helper, because it's unavailable directly in async
  contexts. Compile with each flag combination.
