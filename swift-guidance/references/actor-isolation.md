# Swift Actor Isolation — MainActor-by-Default

## Overview

Modern projects set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in its build settings by default. This opt-in Swift 6 mode changes the default isolation of all declarations — types, functions, properties — to `@MainActor` unless they are explicitly annotated otherwise.

It's a strict mode that catches real bugs (UI updates from background threads), but it also generates warnings on value types and pure logic that have no business being tied to the main thread. Understanding the rules lets you suppress those warnings correctly.

---

## What the Setting Does

Without this setting, unannotated code is **nonisolated** — it can run on any thread. With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, unannotated code is implicitly **`@MainActor`**. This means:

```swift
// Without the setting: callable from any context
struct Post: Codable { ... }

// With the setting: implicitly @MainActor, generates warnings
// when used from async contexts that aren't the main actor
struct Post: Codable { ... }
```

The compiler will warn anywhere a `@MainActor`-isolated type is used from a non-main context — for example, inside an `actor` or a `Task` that isn't guaranteed to be on the main thread.

---

## Value Types: The Safe Case

Immutable value types (structs with no mutable state) are inherently concurrency-safe. No actor isolation is needed because there is nothing to protect — the value is copied, not shared.

**Rule:** A `struct` that is immutable and `Sendable` should be marked `nonisolated` to opt it out of the implicit `@MainActor` isolation.

```swift
// ✅ Correct — immutable struct, safe to use from any context
nonisolated struct Post: Identifiable, Sendable, Codable {
    let id: String
    let groupID: String
    let text: String
    let createdAt: Date
}
```

**When a struct has mutable (`var`) fields**, it is still `Sendable` by default because struct mutation always produces a new copy — the original is not shared. `nonisolated` is still correct:

```swift
// ✅ Also correct — var fields on a struct are copy-on-write, not shared
nonisolated struct Event: Identifiable, Sendable, Codable {
    let id: String
    var title: String       // mutable, but struct semantics mean it's still safe
    var rsvps: [RSVP]
}
```

The key test: **"Could two threads concurrently mutate the same memory?"** For structs, the answer is always no — each caller holds its own copy.

---

## Protocols

### Protocol Isolation Inheritance — Hidden Source of Bugs

When a protocol itself is isolated to an actor, **all implementations of that protocol automatically inherit that isolation**. This can be the cause of extremely difficult bugs to diagnose.

**Problem: Protocol isolated to MainActor**

```swift
// ⚠️ PROBLEM: If this protocol is implicitly @MainActor...
protocol PostsService: Sendable {
    func fetchPosts(groupID: String) async throws -> [Post]
}

// ...then ANY conformance is ALSO implicitly @MainActor
actor NetworkPostsService: PostsService {
    // These methods are implicitly @MainActor, not actor-isolated!
    // They will deadlock if called from the actor!
    func fetchPosts(groupID: String) async throws -> [Post] {
        // This runs on MainActor, not on the actor
        // Causes reentrancy violations and deadlocks
    }
}
```

### Solution: Explicitly Mark Protocol Requirements

Mark protocol methods as `nonisolated` to prevent implicit MainActor isolation on implementations:

```swift
// ✅ SAFE: Requirements are nonisolated
protocol PostsService: Sendable {
    nonisolated func fetchPosts(groupID: String) async throws -> [Post]
    nonisolated func createPost(_ post: Post) async throws -> Post
}

// ✅ Now implementations can be actor-isolated as intended
actor NetworkPostsService: PostsService {
    func fetchPosts(groupID: String) async throws -> [Post] {
        // Correctly runs on the actor
    }
}
```

Alternatively, mark the entire protocol as `nonisolated`:

```swift
// ✅ Entire protocol is nonisolated
nonisolated protocol PostsService: Sendable {
    func fetchPosts(groupID: String) async throws -> [Post]
    func createPost(_ post: Post) async throws -> Post
}

// ✅ Implementations are free to choose their own isolation
actor NetworkPostsService: PostsService {
    func fetchPosts(groupID: String) async throws -> [Post] {
        // Runs on the actor
    }
}
```

### Key Rules

1. **If a protocol is `@MainActor`-isolated** (implicitly or explicitly), all implementations inherit that isolation
2. **To allow flexible isolation**, mark protocol methods as `nonisolated`
3. **To prevent inheritance**, make the entire protocol `nonisolated`
4. **In MainActor-by-default projects**, be especially careful — unannotated protocols become `@MainActor` by default

---

## Actors

`actor` types have their own **actor isolation** which is separate from `@MainActor`. The compiler knows they protect their own state and does not apply the default `@MainActor` to them. No annotation is needed.

```swift
// ✅ No annotation needed — actor isolation is explicit and separate from @MainActor
actor MockPostsService: PostsService {
    private var posts: [Post] = []
    func fetchPosts(groupID: String) async throws -> [Post] { ... }
}
```

---

## Classes

Classes that need to be `Sendable` (e.g., a coordinator or service object shared across contexts) are the hardest case because class instances are reference types with shared mutable state.

Options:

1. **Make it an actor** — the right choice when the class manages state accessed from multiple tasks.
2. **Mark `@unchecked Sendable`** — use sparingly for classes where you manually guarantee thread safety (e.g., via a lock), or for mock/test objects that are never actually shared. Document why.
3. **Keep `@MainActor`** — correct for objects that only ever live on the main thread (e.g., view models, `@Observable` store objects).

```swift
// Mock: @unchecked Sendable is acceptable — single-threaded use in tests
final class MockAuthService: AuthService, @unchecked Sendable { ... }

// Real coordinator: @MainActor if it only wires views and is accessed from UI
@MainActor final class CommunityCoordinator { ... }
```

---

## File-Scoped Loggers

`Logger` is a value type and is safe to use from any context. File-scoped logger constants should always be `nonisolated` to avoid a spurious `@MainActor` inference:

```swift
nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "DataStore")
```

---

## Quick Reference

| Declaration | Annotation | Reason |
|---|---|---|
| Immutable or value-type `struct` | `nonisolated` | Copy semantics; no shared mutable state |
| Protocol with async requirements | `nonisolated` on requirements or protocol | Implementations live on actors, not main thread |
| `actor` | none | Actor isolation is already explicit |
| `@Observable` / UI class | `@MainActor` (or default) | Lives on the main thread |
| Service/coordinator class | `actor` or `@unchecked Sendable` | Depends on access pattern |
| File-scoped `Logger` constant | `nonisolated private let` | Value type; safe from any context |

---

## Code Review Checklist

When reviewing code in a `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project:

- [ ] **Data Models**: Immutable `struct` types marked with `nonisolated`
- [ ] **Codable Types**: Immutable Codable structs marked `nonisolated`
- [ ] **Service Protocols**: Async methods or protocol marked `nonisolated`
- [ ] **Actor Types**: No annotation needed; actor isolation is explicit
- [ ] **View Models**: Annotated with `@MainActor` or using default isolation correctly
- [ ] **Observables**: `@Observable` view models use `@MainActor` correctly
- [ ] **Loggers**: All file-scoped loggers declared as `nonisolated private let`
- [ ] **Shared State**: Classes with mutable state are `actor` or `@unchecked Sendable`
- [ ] **Test Mocks**: Mocks properly marked `@unchecked Sendable` with documentation
- [ ] **Build Settings**: Project has `SWIFT_DEFAULT_ACTOR_ISOLATION` set to `MainActor`
- [ ] **No Warnings**: No isolation-related compiler warnings
- [ ] **Tests Pass**: Test suite passes with strict isolation enabled
