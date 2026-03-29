# Swift Concurrency

Never use Combine or Dispatch for concurrency. Always use modern Swift Concurrency (async/await, Task, actors).

---

## Core Principles

1. **Use async/await** — The standard for asynchronous code in Swift 5.5+
2. **Avoid DispatchQueue, Combine, and callbacks** — These are legacy patterns
3. **Use Task for fire-and-forget work** — Structured concurrency ensures cleanup
4. **Use actors for shared mutable state** — Thread-safe by design
5. **Use @MainActor for UI-bound code** — Compile-time safety for main thread access

---

## async/await vs Callbacks

**Problem with callbacks:**
```swift
// ❌ AVOID: Callback hell, harder to follow control flow
func fetchUser(id: String, completion: @escaping (User?, Error?) -> Void) {
    URLSession.shared.dataTask(with: url) { data, _, error in
        if let error = error {
            completion(nil, error)
            return
        }
        let user = try? JSONDecoder().decode(User.self, from: data!)
        completion(user, nil)
    }.resume()
}
```

**Solution with async/await:**
```swift
// ✅ PREFERRED: Linear flow, clearer error handling
func fetchUser(id: String) async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}

// Usage
let user = try await fetchUser(id: "123")
```

---

## Task, Task Groups, and Structured Concurrency

### Basic Task Usage

```swift
// ✅ Fire-and-forget background work
Task {
    let result = await expensiveComputation()
    updateUI(result)  // Resumes on main thread if called from @MainActor context
}

// ✅ Detached task (for truly independent work)
Task.detached {
    await backgroundWork()  // Not part of parent task hierarchy
}

// ✅ Check for cancellation
Task {
    while !Task.isCancelled {
        await doWork()
    }
}
```

### Coordinating Multiple Async Operations

```swift
// ❌ AVOID: Unstructured concurrency with multiple Tasks
Task { await fetchUsers() }
Task { await fetchPosts() }
Task { await fetchComments() }
// No way to know when all complete or handle errors together

// ✅ PREFERRED: Structured concurrency with TaskGroup
Task {
    let results = await withTaskGroup(of: Result.self) { group in
        group.addTask { await fetchUsers() }
        group.addTask { await fetchPosts() }
        group.addTask { await fetchComments() }

        var collected: [Result] = []
        for await result in group {
            collected.append(result)
        }
        return collected
    }
    updateUI(with: results)
}
```

### Limiting Concurrency

When you need to limit how many tasks run concurrently (e.g., API rate limiting):

```swift
// ✅ Process items with limited concurrency
let results = await withTaskGroup(of: Result.self) { group in
    var pending = items.makeIterator()
    let maxConcurrency = 3
    var activeTasks = 0

    // Fill initial batch
    while activeTasks < maxConcurrency, let item = pending.next() {
        group.addTask { await processItem(item) }
        activeTasks += 1
    }

    // As tasks complete, add more
    var collected: [Result] = []
    for await result in group {
        collected.append(result)
        if let item = pending.next() {
            group.addTask { await processItem(item) }
        } else {
            activeTasks -= 1
        }
    }
    return collected
}
```

---

## Cancellation and withTaskCancellationHandler

```swift
// ✅ Respond to cancellation
Task {
    await withTaskCancellationHandler {
        // Main work
        while !Task.isCancelled {
            await doWork()
        }
    } onCancel: {
        // Cleanup: called when Task is cancelled
        cleanupResources()
    }
}

// ✅ Check for cancellation in loops
Task {
    for item in items {
        guard !Task.isCancelled else { break }
        await processItem(item)
    }
}
```

---

## Avoiding Common Mistakes

### Don't Mix async/await with Callbacks

```swift
// ❌ AVOID: Mixing paradigms
func fetchAndUpdate(completion: @escaping (User?) -> Void) {
    Task {
        let user = try await fetchUser()
        completion(user)  // Mixing callback with async/await
    }
}

// ✅ PREFERRED: Pure async/await
func fetchAndUpdate() async -> User {
    return try await fetchUser()
}
```

### Don't Use Task Without Storing the Handle

```swift
// ❌ PROBLEM: Task is immediately deallocated if not stored
func startBackgroundWork() {
    Task {
        await longRunningTask()  // May be cancelled before it completes
    }
}

// ✅ PREFERRED: Store the task if you need to manage its lifecycle
var backgroundTask: Task<Void, Never>?

func startBackgroundWork() {
    backgroundTask = Task {
        await longRunningTask()
    }
}

func stopBackgroundWork() {
    backgroundTask?.cancel()
    backgroundTask = nil
}
```

### Don't Call Async Functions Without Awaiting

```swift
// ❌ WRONG: Forgot to await
Task {
    let user = fetchUser()  // Returns Task, not User!
}

// ✅ CORRECT: Always await async functions
Task {
    let user = try await fetchUser()
}
```

---

## MainActor and UI Updates

```swift
// ✅ Mark view models and UI coordinators as @MainActor
@MainActor
class UserViewModel: Observable {
    @ObservationIgnored private(set) var user: User?

    func loadUser(id: String) async throws {
        self.user = try await fetchUser(id: id)
    }
}

// ✅ UI updates from background tasks
Task {
    let user = try await fetchUser(id: "123")
    await MainActor.run {
        viewModel.user = user
    }
}
```

Note: If `SWIFT_DEFAULT_ACTOR_ISOLATION` is set to `MainActor` it will not be necessary to explicitly isolate view models to MainActor.

---

## Protocols and Generic Constraints

When defining async protocols, use `Sendable` and proper isolation:

```swift
// ✅ Async service protocol
protocol UserService: Sendable {
    nonisolated func fetchUser(id: String) async throws -> User
    nonisolated func createUser(_ user: User) async throws -> User
}

// ✅ Generic constraint for concurrent types
func process<T: Sendable>(item: T) async {
    // Can safely share T across task boundaries
}
```

---

## Code Review Checklist

When reviewing Swift code for concurrency:

- [ ] Callback-based APIs replaced with async/await
- [ ] DispatchQueue usage replaced with Task (see performance.md for details)
- [ ] Combine publishers replaced with async/await where possible
- [ ] Shared mutable state protected with `actor` instead of `NSLock`
- [ ] UI code annotated with `@MainActor`
- [ ] Resource cleanup uses `withTaskCancellationHandler`
- [ ] Long-running Task handles stored if lifecycle needs to be managed
- [ ] Service protocols marked with `Sendable`
- [ ] Cancellation scenarios handled correctly
