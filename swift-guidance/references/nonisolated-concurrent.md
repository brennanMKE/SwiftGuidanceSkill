# Swift Concurrency: `nonisolated async`, `nonisolated(nonsending)`, and `@concurrent`

## Overview

Where a `nonisolated async` function runs depends on a **compiler setting**,
not just the Swift version. This document explains:

- What `nonisolated` means
- The two execution models for `nonisolated async` and how to tell which one
  a project uses
- `nonisolated(nonsending)` and `@concurrent` — the explicit spellings that
  mean the same thing in every configuration

Behavior below was verified with Swift 6.4 by running code under each flag
combination (`Thread.isMainThread` inside the callee).

---

## What `nonisolated` Means

A `nonisolated` declaration is **not isolated to any actor**, even if it is
declared inside one.

```swift
actor Cache {
    var storage: [String: Data] = [:]

    nonisolated func hash(_ key: String) -> Int {
        key.hashValue
    }
}
```

- `hash` is not actor-isolated
- It cannot access `storage`
- It does not require `await`

Synchronous `nonisolated` functions always run on the caller's thread/actor.

---

## The Two Models for `nonisolated async`

### Model 1 — leaves the caller's actor (SE-0338)

This is the behavior in **Swift 5 and Swift 6 language modes by default**.

```swift
@MainActor
func caller() async {
    await work()
}

nonisolated func work() async {
    // runs on the global concurrent executor — off the main actor
}
```

### Model 2 — runs on the caller's actor (SE-0461, Swift 6.2+)

Enabled by the **`NonisolatedNonsendingByDefault`** upcoming feature. It is
**not** turned on by the Swift 6 language mode. It's enabled by:

- Xcode: `SWIFT_APPROACHABLE_CONCURRENCY = YES` (on in Xcode 26+/27 app templates)
- SwiftPM: `.enableUpcomingFeature("NonisolatedNonsendingByDefault")`
- Command line: `-enable-upcoming-feature NonisolatedNonsendingByDefault`

```swift
@MainActor
func caller() async {
    await work()
}

nonisolated func work() async {
    // runs on the main actor — no hop
}
```

### Verified behavior

| Configuration | `nonisolated async` called from `@MainActor` | `@concurrent` |
|---|---|---|
| Swift 6 mode | **off** main | off main |
| Swift 6 + `-default-isolation=MainActor` | **off** main | off main |
| Swift 6 + `NonisolatedNonsendingByDefault` | **on** main | off main |
| Swift 5 + `NonisolatedNonsendingByDefault` | **on** main | off main |

**Before reviewing `nonisolated async` code, check the build settings** (see
`project-configuration.md`). A Swift package that sets only
`.defaultIsolation(MainActor.self)` is in Model 1, even when the app using it
is in Model 2.

---

## Explicit Spellings (Same Meaning in Every Configuration)

### `nonisolated(nonsending)` — run on the caller's actor

```swift
nonisolated(nonsending) func work() async {
    // always runs on the caller's actor, with or without the upcoming feature
}
```

Use it in code that must behave the same across targets (shared packages),
or to adopt Model 2 for one function before enabling the feature.

### `@concurrent` — always leave the caller's actor

```swift
struct ImageProcessor {
    @concurrent
    func decode(_ data: Data) async -> CGImage? {
        // always runs on the global concurrent executor
    }
}

@MainActor
func show(_ data: Data) async {
    let image = await ImageProcessor().decode(data)   // hops off main, back after
}
```

Arguments and results crossing into a `@concurrent` function must be
`Sendable` (or disconnected values).

`@concurrent` implies `nonisolated`. Writing `@concurrent nonisolated` is
accepted (redundant); `nonisolated @concurrent` is a parse error, because
attributes must come before modifiers.

---

## Rules for `@concurrent` (all verified as compile errors)

### 1. Only for async functions

```swift
@concurrent
func invalid() { }
// ❌ error: cannot use @concurrent on non-async global function 'invalid()'
```

### 2. Implies `nonisolated`

```swift
@concurrent func work() async { }
// same isolation as: nonisolated func work() async { }  under Model 1
```

### 3. Cannot combine with another isolation

```swift
@MainActor @concurrent
func invalid() async { }
// ❌ error: global function 'invalid()' has multiple actor-isolation attributes (@MainActor and @concurrent)
```

### 4. Cannot access actor state

`@concurrent` is allowed on a method declared inside an actor, but the method
is nonisolated:

```swift
actor Store {
    var value = 0

    @concurrent
    func update() async {
        value += 1
        // ❌ error: actor-isolated property 'value' can not be mutated from a nonisolated context
    }
}
```

---

## When to Use `@concurrent`

Use it when:

- The caller is (or may be) on the main actor
- The function does CPU-heavy or blocking work (decoding, parsing, image processing)
- You want the hop to be explicit and independent of build settings

Don't use it on functions that just `await` other async APIs (e.g. `URLSession`)
— those suspend without blocking, so running on the caller's actor is fine.

---

## Code Review Guidance

1. **Determine the model first.** Check `SWIFT_APPROACHABLE_CONCURRENCY` /
   `NonisolatedNonsendingByDefault`. Don't assume Swift 6 mode implies Model 2.
2. **Heavy work in `nonisolated async` under Model 2** runs on the caller's
   actor — often the main actor. Mark it `@concurrent`.
3. **Code that relies on Model 1 hopping** (heavy work in `nonisolated async`
   in a Swift 6 project without the feature) breaks silently when the feature
   is enabled. Make the intent explicit with `@concurrent`.
4. **Shared packages**: prefer `nonisolated(nonsending)` / `@concurrent` over
   relying on the default, since consumers and the package may be configured
   differently.
5. **`@concurrent` must not touch actor state** and can't be combined with
   `@MainActor` or other isolation.

---

## Summary

| Declaration | Runs on |
|--------|--------|
| `@MainActor func f() async` | main actor |
| `nonisolated func f()` (sync) | caller's context |
| `nonisolated func f() async` — default | **off** the caller's actor |
| `nonisolated func f() async` — `NonisolatedNonsendingByDefault` | caller's actor |
| `nonisolated(nonsending) func f() async` | caller's actor (any configuration) |
| `@concurrent func f() async` | global concurrent executor (any configuration) |

---

## Key Takeaways

- The Swift 6 language mode does **not** change where `nonisolated async` runs;
  the `NonisolatedNonsendingByDefault` feature does
- Xcode's Approachable Concurrency enables it; SwiftPM needs it by name
- `@concurrent` and `nonisolated(nonsending)` are explicit and portable — prefer
  them where behavior matters
