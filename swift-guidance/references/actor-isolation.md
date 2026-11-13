# Swift Actor Isolation — MainActor-by-Default

## Overview

New Xcode 26/27 app templates set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466, Swift 6.2+). It changes the default isolation of declarations — types, functions, properties, protocol requirements — to `@MainActor` unless they are explicitly annotated otherwise. Actors keep their own isolation.

Rules below were verified by compiling with `-swift-version 6 -default-isolation=MainActor` (Swift 6.4), with and without the approachable-concurrency features.

It's a strict mode that catches real bugs (UI updates from background threads), but it also generates warnings on value types and pure logic that have no business being tied to the main thread. Understanding the rules lets you suppress those warnings correctly.

---

## What the Setting Does

Without this setting, unannotated code is **nonisolated** — it can run on any thread. With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, unannotated code is implicitly **`@MainActor`**. This means:

```swift
// With the setting, this struct, its methods, and its Codable conformance are @MainActor
struct Event: Codable {
    var title: String
    func shout() -> String { title.uppercased() }
}

actor Importer {
    func f(_ e: Event) throws -> String {
        _ = e.title                        // ✅ reading stored properties is fine
        _ = try JSONEncoder().encode(e)    // ❌ main actor-isolated conformance of 'Event' to 'Encodable' cannot be used in nonisolated context
        return e.shout()                   // ❌ call to main actor-isolated instance method 'shout()' in a synchronous actor-isolated context
    }
}
```

In Swift 6 mode these are errors. They show up when a `@MainActor`-by-default
type's **methods or conformances** (`Codable`, `Hashable`, `Equatable`, …) are
used from an actor, a `@concurrent` function, or other nonisolated code.

---

## Value Types: The Safe Case

Immutable value types (structs with no mutable state) are inherently concurrency-safe. No actor isolation is needed because there is nothing to protect — the value is copied, not shared.

**Rule:** Data-model value types used off the main actor (decoded on a background task, passed to actors, used in services) should be marked `nonisolated` so their methods and conformances aren't `@MainActor`.

```swift
// ✅ Correct — immutable struct, safe to use from any context
nonisolated struct Post: Identifiable, Sendable, Codable {
    let id: String
    let groupID: String
    let text: String
    let createdAt: Date
}
```

**When a struct has mutable (`var`) fields**, it can still be `Sendable`: mutation changes the caller's copy, not a shared one. `nonisolated` is still correct:

```swift
// ✅ Also correct — var fields on a struct are copy-on-write, not shared
nonisolated struct Event: Identifiable, Sendable, Codable {
    let id: String
    var title: String       // mutable, but struct semantics mean it's still safe
    var rsvps: [RSVP]
}
```

The key test: **"Could two threads concurrently mutate the same memory?"** For a struct whose stored properties are all `Sendable`, no. Two caveats (both compile errors in Swift 6):

- A struct holding a **non-`Sendable` class reference** shares that object between copies, so it can't be `Sendable` — "stored property 'box' of 'Sendable'-conforming struct 'Holder' has non-Sendable type 'Box'".
- `Sendable` is only **inferred for non-`public`** structs. `public` types must declare `: Sendable` explicitly.

---

## Protocols

### Protocol Requirements Default to `@MainActor`

Under MainActor default isolation, an unannotated protocol's requirements are
`@MainActor`. That doesn't move an actor's implementation onto the main
actor — an actor's methods still run on the actor (verified: off the main
thread, with access to actor state), and calling them through the protocol
with `await` hops to the actor. Swift actors don't deadlock this way.

What it *does* do is make the protocol unusable from nonisolated code:

```swift
// ⚠️ PROBLEM: requirement is implicitly @MainActor
protocol Named {
    func name() -> String
}

nonisolated func label(for item: any Named) -> String {
    item.name()
    // ❌ error: call to main actor-isolated instance method 'name()' in a synchronous nonisolated context
}
```

Every caller must be on the main actor (or `await` an async requirement),
and conforming types that aren't main-actor-isolated need `nonisolated`
witnesses.

### Solution: Explicitly Mark Protocol Requirements

Mark protocol requirements `nonisolated` when the protocol is used from non-main code:

```swift
// ✅ SAFE: Requirements are nonisolated
protocol PostsService: Sendable {
    nonisolated func fetchPosts(groupID: String) async throws -> [Post]
    nonisolated func createPost(_ post: Post) async throws -> Post
}

// ✅ Callable from any isolation; actor implementations run on the actor
actor NetworkPostsService: PostsService {
    func fetchPosts(groupID: String) async throws -> [Post] { ... }
    func createPost(_ post: Post) async throws -> Post { ... }
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

1. **In MainActor-by-default modules**, unannotated protocol requirements are `@MainActor`
2. **Service and model protocols used off the main actor** should be `nonisolated` (per requirement or for the whole protocol)
3. **Actor conformances still run on the actor** — the issue is caller isolation, not deadlocks
4. **UI-only protocols** can stay `@MainActor`

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

1. **Make it an actor** — the right choice when the state is accessed from multiple tasks and `async` access is acceptable.
2. **Protect state with `Mutex`** (Synchronization, iOS 18 / macOS 15+) — when access must stay synchronous. The class is checked `Sendable` with no `@unchecked`:
   ```swift
   import Synchronization

   nonisolated final class Counter: Sendable {
       private let state = Mutex(0)
       func increment() -> Int { state.withLock { $0 += 1; return $0 } }
   }
   ```
3. **Mark `@unchecked Sendable`** — last resort for classes whose safety the compiler can't see (an older lock, a thread-safe C API), or mocks that are never shared. Document why.
4. **Keep `@MainActor`** — correct for objects that only ever live on the main thread (e.g., view models, `@Observable` store objects).

```swift
// Mock: @unchecked Sendable is acceptable — single-threaded use in tests
final class MockAuthService: AuthService, @unchecked Sendable { ... }

// Real coordinator: @MainActor if it only wires views and is accessed from UI
@MainActor final class CommunityCoordinator { ... }
```

---

## File-Scoped Loggers

`Logger` is `Sendable`, and a file-scoped `let` of a `Sendable` type is usable from any isolation even under MainActor default isolation (verified: a plain `private let logger` compiles when used from an actor and a nonisolated function). Marking it `nonisolated` is optional — it documents intent and is harmless:

```swift
nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "DataStore")
```

Don't flag a missing `nonisolated` on a `Sendable` global `let` as an issue.

---

## Quick Reference

| Declaration | Annotation | Reason |
|---|---|---|
| Data-model `struct` used off main | `nonisolated` | Methods and conformances (`Codable`) otherwise `@MainActor` |
| Protocol used from non-main code | `nonisolated` on requirements or protocol | Requirements otherwise `@MainActor` |
| `actor` | none | Actor isolation is already explicit |
| `@Observable` / UI class | `@MainActor` (or default) | Lives on the main thread |
| Service/coordinator class | `actor`, or `Sendable` + `Mutex` | Async vs synchronous access |
| File-scoped `Logger` constant | `private let` (`nonisolated` optional) | `Sendable`; usable from any isolation |

---

## Code Review Checklist

When reviewing code in a `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project:

- [ ] **Data Models**: value types used off the main actor marked `nonisolated`
- [ ] **Codable Types**: Codable models encoded/decoded off-main marked `nonisolated` (otherwise the conformance is `@MainActor`)
- [ ] **Service Protocols**: requirements or protocol marked `nonisolated` when used from non-main code
- [ ] **Actor Types**: No annotation needed; actor isolation is explicit
- [ ] **View Models**: Annotated with `@MainActor` or using default isolation correctly
- [ ] **Observables**: `@Observable` view models use `@MainActor` correctly
- [ ] **Shared State**: Classes with mutable state are `actor`, `Mutex`-protected `Sendable`, or (documented) `@unchecked Sendable`
- [ ] **Test Mocks**: Mocks properly marked `@unchecked Sendable` with documentation
- [ ] **Build Settings**: Project enables MainActor default isolation and strict concurrency (see `project-configuration.md`)
- [ ] **No Errors**: Builds cleanly in Swift 6 mode
- [ ] **Tests Pass**: Test suite passes with strict isolation enabled
