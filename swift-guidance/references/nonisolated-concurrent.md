# Swift Concurrency: `nonisolated` Evolution and `@concurrent`

## Overview

Swift's concurrency model has evolved significantly between Swift 5 and Swift 6, especially around how `nonisolated` async functions behave.

This document explains:

- What `nonisolated` means
- How its behavior changed over time
- How it behaves in Swift 6
- How to use `@concurrent` to explicitly leave actor isolation

---

## What `nonisolated` Means

`nonisolated` means:

> A function is **not isolated to any actor**, even if it is declared inside one.

Example:

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

---

## Historical Behavior (Swift 5.7 – Swift 6 baseline)

### SE-0338 Model

In earlier Swift concurrency:

> `nonisolated async` functions **never ran on an actor's executor**

That means:

```swift
@MainActor
func caller() async {
    await work()
}

nonisolated func work() async {
    // runs off MainActor
}
```

Behavior:

- Calling `work()` **leaves MainActor**
- It runs on a generic executor
- Execution returns to MainActor after `await`

### Important Distinction

| Function Type | Behavior |
|------|--------|
| `nonisolated sync` | Runs on caller's actor |
| `nonisolated async` | Leaves actor |

This inconsistency was confusing.

---

## New Behavior (Swift Evolution SE-0461)

Swift introduces a new model to unify behavior.

### Key Change

> `nonisolated async` functions can now run on the **caller's actor by default**

This behavior is enabled with:

- Swift 6+
- `NonisolatedNonsendingByDefault` feature

### New Default Behavior

```swift
@MainActor
func caller() async {
    await work()
}

nonisolated func work() async {
    // runs on MainActor (by default in new model)
}
```

Now:

- No automatic actor hop
- Matches synchronous behavior

---

## Why This Change Matters

Before:

- `await` often implied an actor hop
- Hard to reason about execution

After:

- Isolation is consistent
- No implicit hops unless explicitly requested

---

## Introducing `@concurrent`

To explicitly force execution **outside of actor isolation**, Swift introduces:

```swift
@concurrent
```

### Definition

> `@concurrent` means the function always runs on the **concurrent executor**, not the caller's actor.

---

## Using `@concurrent`

### Basic Example

```swift
struct Processor {
    @concurrent
    func process(_ data: Data) async -> Data {
        data
    }
}
```

### Calling from MainActor

```swift
@MainActor
func run() async {
    let result = await Processor().process(Data())
}
```

Behavior:

1. Start on MainActor
2. Call `process`
3. Leave MainActor
4. Run on concurrent executor
5. Resume on MainActor

---

## Rules for `@concurrent`

### 1. Only for async functions

```swift
@concurrent
func invalid() { } // ❌ not allowed
```

---

### 2. Implies `nonisolated`

```swift
@concurrent
func work() async { }
```

Equivalent to:

```swift
nonisolated func work() async { }
```

---

### 3. Cannot combine with actor isolation

```swift
@MainActor
@concurrent
func invalid() async { } // ❌ error
```

---

### 4. Cannot access actor state

```swift
actor Store {
    var value = 0

    @concurrent
    func update() async {
        value += 1 // ❌ error
    }
}
```

---

## When to Use `@concurrent`

Use it when:

- You are on `MainActor`
- You want to perform heavy work off the UI thread
- You want explicit control over execution

Example:

```swift
struct ImageProcessor {
    @concurrent
    func decode(_ data: Data) async -> Image {
        Image()
    }
}
```

---

## Mental Model

### Old Model

- `nonisolated async` → always leaves actor

### New Model

- `nonisolated async` → stays on caller actor (default)
- `@concurrent` → explicitly leaves actor

---

## Code Review Guidance

When reviewing code:

1. **Check if `nonisolated async` is intended to leave isolation** — In Swift 6+ with the new model, it won't. If the function needs to run off-actor, use `@concurrent` instead.

2. **Flag misused `@concurrent`** — `@concurrent` should only be used when you explicitly need to hop off the caller's actor. If the function is naturally nonisolated, just use `nonisolated` (or don't annotate).

3. **Verify actor state access** — Functions marked `@concurrent` cannot access actor-isolated state. If they do, remove `@concurrent` or refactor to not access actor state.

4. **MainActor considerations** — Heavy computation on MainActor should use `@concurrent` to explicitly move work to a background thread. UI updates need to return to MainActor.

---

## Summary

| Feature | Behavior |
|--------|--------|
| `@MainActor` | Runs on main actor |
| `nonisolated` | Not actor-isolated |
| `nonisolated async` (old) | Leaves actor |
| `nonisolated async` (new) | Inherits caller actor |
| `@concurrent` | Forces concurrent executor |

---

## Key Takeaways

- Isolation is determined by the function declaration
- Swift 6 reduces implicit actor hops
- `@concurrent` is the explicit way to run work off an actor
- Prefer explicit isolation for clarity and correctness
