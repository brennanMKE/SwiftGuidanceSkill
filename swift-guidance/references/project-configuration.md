# Project Configuration — MainActor Default Isolation & Strict Concurrency

## Overview

Modern Swift projects should enable **MainActor-by-default isolation** together with **complete strict concurrency checking**. This combination gives the safest, most ergonomic baseline: UI code is correct by default, and the compiler catches data races at build time. The "approachable concurrency" mode smooths the migration so the strict settings produce fewer spurious errors.

These are project- and package-level build settings, not source annotations. Set them once and every file inherits the behavior. (For the per-declaration `nonisolated` / `@MainActor` annotations these settings imply, see `actor-isolation.md`.)

---

## Xcode Projects

Set these three build settings on the target (or project). They are available in Xcode 26+ with the Swift 6.2 toolchain:

```
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_STRICT_CONCURRENCY = complete
```

### What Each Setting Does

- **`SWIFT_APPROACHABLE_CONCURRENCY = YES`** — Enables the "approachable concurrency" upcoming features (e.g. `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`). These make `nonisolated async` functions stay on the caller's actor by default and reduce false-positive concurrency errors, making the strict settings practical to adopt.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — Makes every unannotated declaration implicitly `@MainActor`. UI-bound code is correct with no annotation; types that must run off the main actor are explicitly marked `nonisolated`.
- **`SWIFT_STRICT_CONCURRENCY = complete`** — Turns on full data-race checking across the whole module, not just code that already adopted concurrency. This is the Swift 6 language mode's checking level.

### Setting Them in xcconfig

Prefer an `.xcconfig` file so the settings are version-controlled and shared across targets:

```xcconfig
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_STRICT_CONCURRENCY = complete
```

In a multiplatform project, these are platform-agnostic — they do **not** need `[sdk=*]` qualifiers (unlike the SDK-specific settings in `multiplatform.md`).

---

## Swift Packages

In `Package.swift`, apply the equivalent settings as `SwiftSetting`s and reuse them across every target. Default isolation requires **swift-tools-version 6.2 or later**:

```swift
// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .defaultIsolation(MainActor.self)
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

- **`.defaultIsolation(MainActor.self)`** — The package-manifest equivalent of `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Unannotated declarations in the target become implicitly `@MainActor`. Passing `nil` (or omitting it) restores `nonisolated` default isolation.
- **`.enableUpcomingFeature("StrictConcurrency")`** — Enables complete strict-concurrency checking, the package equivalent of `SWIFT_STRICT_CONCURRENCY = complete`. When the target builds under the Swift 6 language mode this checking is already on; the upcoming feature opts in while still on an earlier language mode.

### Apply to Every Target

Declare `swiftSettings` once and pass the same array to **all** targets — including test targets. Inconsistent settings between targets lead to confusing isolation mismatches where a test can't call into code it should be able to reach.

---

## Common Pitfalls

- **Setting isolation but not strict concurrency (or vice versa)** — Use both. MainActor-by-default without strict checking hides races; strict checking without the approachable-concurrency features produces noisy false positives.
- **Forgetting test targets** — Test targets need the same settings as the code they exercise.
- **Tools version too low** — `.defaultIsolation` requires `swift-tools-version: 6.2`. On older toolchains the manifest won't compile.
- **Adding `[sdk=*]` to these settings in Xcode** — They are platform-independent; qualifying them per-SDK is unnecessary and easy to get wrong.
- **Expecting zero warnings immediately** — Enabling these on an existing codebase surfaces real isolation work. Annotate value types and off-main services `nonisolated` (see `actor-isolation.md`) rather than disabling the settings.

---

## Code Review Checklist

When reviewing project or package configuration:

**Xcode projects:**
- [ ] `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- [ ] `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- [ ] `SWIFT_STRICT_CONCURRENCY = complete`
- [ ] Settings live in a version-controlled `.xcconfig` where practical
- [ ] These settings are **not** unnecessarily qualified with `[sdk=*]`

**Swift packages:**
- [ ] `swift-tools-version` is `6.2` or later
- [ ] A shared `swiftSettings` array includes `.defaultIsolation(MainActor.self)`
- [ ] The same array includes `.enableUpcomingFeature("StrictConcurrency")`
- [ ] `swiftSettings` is applied to **every** target, including test targets

**Both:**
- [ ] Resulting isolation warnings are resolved with `nonisolated` annotations, not by disabling the settings (see `actor-isolation.md`)
