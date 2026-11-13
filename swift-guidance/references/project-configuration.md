# Project Configuration — Swift 6, MainActor Default Isolation & Approachable Concurrency

## Overview

Modern Swift projects should build in the **Swift 6 language mode** with
**MainActor-by-default isolation** and the **approachable concurrency**
features. Swift 6 mode turns on complete data-race checking as *errors*;
MainActor default isolation makes UI code correct without annotations; the
approachable-concurrency features make `nonisolated async` functions run on the
caller's actor and infer isolated conformances, removing most false positives.

These are project- and package-level build settings, not source annotations.
(For the per-declaration `nonisolated` / `@MainActor` annotations these
settings imply, see `actor-isolation.md`.)

Verified with Xcode 27.2 / Swift 6.4 by building a real `.xcodeproj` and a
Swift package and inspecting the `swiftc` flags and runtime behavior.

---

## Xcode Projects

Set these on the target (or project):

```
SWIFT_VERSION = 6.0
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

**New Xcode 27 app templates set `SWIFT_VERSION = 5.0`** (along with
`SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`). Change it to `6.0` — in Swift 5 mode, data-race diagnostics are
warnings at most.

### What Each Setting Does

- **`SWIFT_VERSION = 6.0`** — Swift 6 language mode. Complete strict
  concurrency checking is always on and data-race diagnostics are errors.
- **`SWIFT_APPROACHABLE_CONCURRENCY = YES`** — passes
  `-enable-upcoming-feature` for:
  - `NonisolatedNonsendingByDefault` (SE-0461) — `nonisolated async`
    functions run on the caller's actor; use `@concurrent` to leave it
  - `InferIsolatedConformances` (SE-0470) — conformances of global-actor
    types are inferred as isolated
  - In Swift 5 mode only, it also enables `DisableOutwardActorInference`,
    `GlobalActorIsolatedTypesUsability`, and `InferSendableFromCaptures`
    (already part of Swift 6 mode)
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — passes
  `-default-isolation=MainActor`. Unannotated declarations are implicitly
  `@MainActor`; types that must run off the main actor are marked
  `nonisolated`.

### `SWIFT_STRICT_CONCURRENCY` is a Swift 5 setting

Xcode's build-setting spec applies `SWIFT_STRICT_CONCURRENCY` only when the
Swift version is 4, 4.2, or 5. Under `SWIFT_VERSION = 6.0` it is ignored —
checking is already complete. Use it (`= complete`) only as a migration step
for a target that can't move to Swift 6 yet.

### Setting Them in xcconfig

Prefer an `.xcconfig` file so the settings are version-controlled and shared
across targets:

```xcconfig
SWIFT_VERSION = 6.0
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

In a multiplatform project, these are platform-agnostic — they do **not**
need `[sdk=*]` qualifiers (unlike the SDK-specific settings in
`multiplatform.md`).

---

## Swift Packages

`swift-tools-version: 6.0` and later build targets in the Swift 6 language
mode by default, so complete checking is already on. SwiftPM has **no**
approachable-concurrency switch — enable the two upcoming features by name, or
package code behaves differently from the same code in an Xcode target
(verified: a `nonisolated async` function called from `@MainActor` ran on the
main actor in the Xcode target and off it in a package that set only
`.defaultIsolation(MainActor.self)`).

`.defaultIsolation` requires **swift-tools-version 6.2 or later**:

```swift
// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "MyLibrary",
    targets: [
        .target(
            name: "MyLibrary",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MyLibraryTests",
            dependencies: ["MyLibrary"],
            swiftSettings: swiftSettings
        )
    ]
)
```

### What Each Setting Does

- **Language mode** — tools version 6.0+ defaults to Swift 6. If a target
  sets `swiftLanguageModes: [.v5]`, add `.enableUpcomingFeature("StrictConcurrency")`
  for complete checking (warnings) while migrating; it's redundant in Swift 6 mode.
- **`.defaultIsolation(MainActor.self)`** — equivalent of
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Passing `nil` (or omitting it)
  keeps `nonisolated` default isolation. Library packages that aren't UI code
  often should omit it.
- **`.enableUpcomingFeature("NonisolatedNonsendingByDefault")`** and
  **`.enableUpcomingFeature("InferIsolatedConformances")`** — what
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` enables in Swift 6 mode.

### Apply to Every Target

Declare `swiftSettings` once and pass the same array to **all** targets —
including test targets. Inconsistent settings between targets lead to
confusing isolation mismatches where a test can't call into code it should be
able to reach.

---

## Common Pitfalls

- **Leaving `SWIFT_VERSION = 5.0` from the template** — data races stay
  warnings (or invisible). Move to `6.0`.
- **Relying on `SWIFT_STRICT_CONCURRENCY` in Swift 6 mode** — it's ignored
  there; it isn't a substitute for the language mode.
- **Package settings that don't match the app's** — without the two upcoming
  features, `nonisolated async` code in a package hops off the caller's
  actor while the identical code in the app target doesn't.
- **Forgetting test targets** — test targets need the same settings as the
  code they exercise.
- **Tools version too low** — `.defaultIsolation` requires
  `swift-tools-version: 6.2`.
- **Adding `[sdk=*]` to these settings in Xcode** — they are
  platform-independent.
- **Expecting zero errors immediately** — moving an existing codebase to
  Swift 6 surfaces real isolation work. Annotate value types and off-main
  services `nonisolated` (see `actor-isolation.md`) rather than dropping back
  to Swift 5 mode.

---

## Code Review Checklist

**Xcode projects:**
- [ ] `SWIFT_VERSION = 6.0` (not the template's `5.0`)
- [ ] `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- [ ] `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app/UI targets)
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` only on targets still in Swift 5 mode
- [ ] Settings live in a version-controlled `.xcconfig` where practical
- [ ] These settings are **not** unnecessarily qualified with `[sdk=*]`

**Swift packages:**
- [ ] `swift-tools-version` is `6.2` or later; targets are not pinned to `.v5`
- [ ] A shared `swiftSettings` array includes `.defaultIsolation(MainActor.self)` (UI-facing targets)
- [ ] The same array enables `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`
- [ ] `swiftSettings` is applied to **every** target, including test targets

**Both:**
- [ ] Resulting isolation errors are resolved with `nonisolated` / `@concurrent` annotations, not by reverting to Swift 5 mode (see `actor-isolation.md`)
