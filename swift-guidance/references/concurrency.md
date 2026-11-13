# Swift Concurrency

Prefer Swift Concurrency (async/await, `Task`, task groups, actors) over
Dispatch and completion handlers for new asynchronous code. Combine remains
reasonable for existing reactive pipelines, but don't use it for one-shot
async work.

Code samples here compile under Swift 6 mode; behavioral claims were verified
by running code with Swift 6.4.

---

## Core Principles

1. **Use async/await** for asynchronous work
2. **Avoid DispatchQueue and completion handlers** in new code
3. **Prefer structured concurrency** (`async let`, task groups) — child tasks
   are awaited and cancelled with their parent
4. **Use unstructured `Task {}` deliberately** — it is *not* structured; keep
   the handle when you need to cancel or await it
5. **Protect shared mutable state** with an actor (async access) or `Mutex`
   (synchronous access)
6. **Use `@MainActor` for UI-bound code** (implicit under MainActor default
   isolation)

---

## async/await vs Callbacks

```swift
// ❌ AVOID: nested callbacks, force-unwraps, easy to forget to call completion
func fetchUser(id: String, completion: @escaping (User?, Error?) -> Void) {
    URLSession.shared.dataTask(with: url) { data, _, error in
        if let error {
            completion(nil, error)
            return
        }
        let user = try? JSONDecoder().decode(User.self, from: data!)
        completion(user, nil)
    }.resume()
}
```

```swift
// ✅ PREFERRED: linear flow, typed errors
func fetchUser(id: String) async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}

let user = try await fetchUser(id: "123")
```

Forgetting `await` is a compile error ("expression is 'async' but is not
marked with 'await'"), so it doesn't need review attention.

### Bridging a callback API you can't change

```swift
func fetchUser(id: String) async throws -> User {
    try await withCheckedThrowingContinuation { continuation in
        legacyClient.fetchUser(id: id) { result in
            continuation.resume(with: result)   // resume exactly once
        }
    }
}
```

---

## Tasks

### Unstructured `Task {}`

```swift
// Inherits the current actor: created on @MainActor → runs on the main actor
Task {
    let result = await expensiveComputation()
    updateUI(result)
}

// Does not inherit the actor, priority, or task-locals
Task.detached {
    await backgroundWork()
}
```

**A `Task` runs to completion whether or not you keep its handle.** Dropping
the handle does not cancel or deallocate it (verified; Apple: "A task runs
regardless of whether you keep a reference to it."). Keep the handle when you
need to **cancel** it or **await its result**:

```swift
// ✅ Store the handle to manage lifetime (e.g. cancel when the owner goes away)
@MainActor
final class Poller {
    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

In SwiftUI, prefer `.task { }` / `.task(id:)` — the view cancels it on
disappear.

### Coordinating Multiple Async Operations

```swift
// ❌ AVOID: independent Tasks — no single point to await, cancel, or handle errors
Task { await fetchUsers() }
Task { await fetchPosts() }

// ✅ PREFERRED: async let for a fixed number of child tasks
async let users = fetchUsers()
async let posts = fetchPosts()
let (u, p) = try await (users, posts)

// ✅ PREFERRED: task group for a dynamic number
let images = try await withThrowingTaskGroup(of: (URL, Image).self) { group in
    for url in urls {
        group.addTask { (url, try await loadImage(url)) }
    }
    var result: [URL: Image] = [:]
    for try await (url, image) in group {
        result[url] = image
    }
    return result
}
```

### Limiting Concurrency

```swift
// ✅ At most `maxConcurrency` child tasks in flight
let results = await withTaskGroup(of: Output.self) { group in
    let maxConcurrency = 3
    var pending = items.makeIterator()

    for _ in 0..<maxConcurrency {
        guard let item = pending.next() else { break }
        group.addTask { await process(item) }
    }

    var collected: [Output] = []
    for await output in group {
        collected.append(output)
        if let item = pending.next() {
            group.addTask { await process(item) }
        }
    }
    return collected
}
```

---

## Cancellation

Cancellation is cooperative: check `Task.isCancelled` or call
`try Task.checkCancellation()`. Many async APIs (`Task.sleep`, `URLSession`)
throw `CancellationError` when cancelled.

```swift
for item in items {
    try Task.checkCancellation()
    await process(item)
}
```

### `withTaskCancellationHandler` is for *reacting* to cancellation, not cleanup

`onCancel` runs **immediately and concurrently** with the operation when the
task is cancelled — and if the task was already cancelled, it runs **before**
the operation starts (both verified; documented by Apple). It must be
thread-safe and is typically used to interrupt something the operation is
blocked on (a non-async API, a continuation, a socket).

```swift
// ✅ Forward cancellation to a callback-based API
func download(_ url: URL) async throws -> Data {
    let request = LegacyRequest(url)
    return try await withTaskCancellationHandler {
        try await request.start()
    } onCancel: {
        request.cancel()   // LegacyRequest.cancel() must be thread-safe
    }
}
```

**Cleanup that must happen however the work ends** (success, error, or
cancellation) belongs in `defer`:

```swift
func process(file: URL) async throws {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    ...
}
```

---

## MainActor and UI Updates

```swift
// ✅ View model: @Observable + @MainActor (implicit under MainActor default isolation)
@MainActor
@Observable
final class UserViewModel {
    private(set) var user: User?

    func loadUser(id: String) async throws {
        user = try await fetchUser(id: id)   // resumes on the main actor
    }
}
```

Don't hand-conform to `Observable` or mark observed properties
`@ObservationIgnored` — without the macro, observers are never notified
(verified), and SwiftUI won't update.

Code already on the main actor doesn't need `MainActor.run`. Use
`await MainActor.run { }` only from a nonisolated context — and prefer calling
a `@MainActor` method instead:

```swift
// From a nonisolated / @concurrent context
let user = try await fetchUser(id: "123")
await viewModel.apply(user)        // @MainActor method; the await hops to main
```

---

## Protocols and Generic Constraints

```swift
// ✅ Service protocol usable from any isolation
nonisolated protocol UserService: Sendable {
    func fetchUser(id: String) async throws -> User
    func createUser(_ user: User) async throws -> User
}

// ✅ Generic constraint for values that cross task boundaries
func process<T: Sendable>(item: T) async { ... }
```

Under MainActor default isolation, unannotated protocol requirements are
`@MainActor` — see `actor-isolation.md`.

---

## Code Review Checklist

- [ ] New async work uses async/await, not completion handlers or DispatchQueue
- [ ] Callback APIs that can't change are bridged with checked continuations (resumed exactly once)
- [ ] Concurrent child work uses `async let` / task groups rather than multiple loose `Task {}`s
- [ ] `Task` handles are kept where the work must be cancelled or awaited (not "to keep it alive")
- [ ] Shared mutable state is protected by an actor or `Mutex`
- [ ] UI state lives in `@MainActor` (`@Observable`) types
- [ ] `withTaskCancellationHandler` `onCancel` closures are thread-safe; cleanup uses `defer`
- [ ] Long loops check cancellation
- [ ] Service protocols are `Sendable` with explicit isolation
