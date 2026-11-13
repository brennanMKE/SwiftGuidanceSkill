# Performance

## Core Principles

1. **Avoid blocking code** — Use modern Swift concurrency (async/await, actors) instead of blocking primitives
2. **Move long-running work off the main thread** — Keep UI responsive
3. **Use Swift concurrency over GCD** — Fewer threads, better scheduling, no thread exhaustion

---

## Blocking Code and Deadlocks

### DispatchSemaphore — Common Source of Problems

**Problem**: Semaphores block threads, which causes several issues:

```swift
// ❌ AVOID: Blocking semaphore
let semaphore = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    fetchData { result in
        semaphore.signal()
    }
}
semaphore.wait()  // Blocks current thread
```

**Why this is problematic**:
- Blocks the calling thread, wasting resources
- Can cause deadlocks if signal/wait are paired incorrectly
- Thread exhaustion: waiting threads consume memory and scheduling overhead
- Unpredictable latency in highly concurrent systems

**Solution**: Use async/await instead:

```swift
// ✅ PREFERRED: Non-blocking async/await
let result = await fetchData()
// Caller is suspended, not blocked
```

---

### NSLock and Manual Locking — Error-Prone, Not Compiler-Checked

**Problem**: hand-rolled locks around separate mutable state aren't checked by
the compiler — nothing stops an access that forgets the lock:

```swift
// ❌ AVOID: lock and state are unrelated as far as the compiler knows
let lock = NSLock()
var cachedData: [String: Data] = [:]

func getData(key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return cachedData[key]
}
```

**Why this is problematic**:
- The compiler can't verify every access takes the lock
- Deadlocks are possible with multiple locks or re-entrant calls
- The surrounding type needs `@unchecked Sendable`, hiding real races

**Solution — choose by access pattern:**

```swift
// ✅ Actor: callers can await; state accessed from many tasks
actor DataCache {
    private var cachedData: [String: Data] = [:]

    func getData(key: String) -> Data? {
        cachedData[key]
    }

    func setData(_ value: Data, for key: String) {
        cachedData[key] = value
    }
}

let value = await cache.getData(key: "user")
```

```swift
// ✅ Mutex (Synchronization, iOS 18 / macOS 15+): access must stay synchronous,
// critical sections are short. The state lives inside the lock, so the compiler
// enforces locked access and the type is checked Sendable.
import Synchronization

final class DataCache: Sendable {
    private let cachedData = Mutex<[String: Data]>([:])

    func getData(key: String) -> Data? {
        cachedData.withLock { $0[key] }
    }

    func setData(_ value: Data, for key: String) {
        cachedData.withLock { $0[key] = value }
    }
}
```

**Trade-offs**:
- Actors serialize too, but suspend callers instead of blocking threads; every
  access becomes `async` and actor methods are re-entrant across `await`s
- `Mutex` blocks briefly, keeps APIs synchronous, and is often faster for tiny
  critical sections; never `await` while holding it (`withLock` doesn't allow it)
- Below iOS 18 / macOS 15, `OSAllocatedUnfairLock(initialState:)` (iOS 16 / macOS 13+) has the same state-inside-the-lock shape

---

## DispatchQueue → Swift Concurrency Migration

### The Problem with GCD DispatchQueue

```swift
// ❌ AVOID: DispatchQueue-heavy pattern
DispatchQueue.global(qos: .userInitiated).async {
    let data = fetchData()
    DispatchQueue.main.async {
        updateUI(data)
    }
}
```

**Issues**:
1. **Thread Exhaustion**: Each `.global()` queue creates threads that persist for cleanup overhead
2. **Thread Starvation**: If many tasks queue up, new threads are created, consuming memory
3. **Context Switching Overhead**: Too many threads cause expensive context switches
4. **Scheduling Unpredictability**: GCD scheduler doesn't know about your async tasks
5. **Manual Cancellation**: only `DispatchWorkItem.cancel()`, which doesn't stop work already running or propagate to child work

### Solution: Swift Concurrency with Tasks and Structured Concurrency

```swift
// ✅ PREFERRED: Swift concurrency
@MainActor
func loadData() async {
    let data = await fetchData()  // Suspends (e.g. network I/O), doesn't block
    updateUI(data)                // Back on the main actor
}

Task {
    await loadData()
}
```

**Benefits**:
- **Unified Executor Model**: Automatic thread pool management
- **Bounded Threads**: Tasks run on a cooperative pool sized to the CPU core count, so no thread explosion — but **never block inside a task** (semaphores, `Thread.sleep`, synchronous I/O, waiting on a lock across slow work): blocked tasks hold pool threads and can starve the whole app
- **Better Scheduling**: Runtime knows about async boundaries
- **Built-in Cancellation**: `Task.isCancelled`, `withTaskCancellationHandler`
- **Structured Concurrency**: Clear parent-child relationships

### Common GCD Patterns → Swift Concurrency

**Pattern 1: Background Work + Main Thread Update**

```swift
// ❌ GCD
DispatchQueue.global().async {
    let result = expensiveComputation()
    DispatchQueue.main.async {
        self.updateUI(result)
    }
}

// ❌ WRONG MIGRATION: a Task created on the main actor runs on the main actor.
// With Approachable Concurrency (NonisolatedNonsendingByDefault), a plain
// nonisolated async function also runs on the caller's actor — so this
// moves the CPU work ONTO the main thread.
Task {
    let result = await expensiveComputation()
    updateUI(result)
}

// ✅ Swift Concurrency: mark the CPU-bound function @concurrent
@concurrent
func expensiveComputation() async -> Output { ... }   // always runs off the caller's actor

Task {
    let result = await expensiveComputation()   // hops off main, then back
    updateUI(result)                            // on the main actor
}
```

See `nonisolated-concurrent.md` for where `nonisolated async` runs under each build configuration.

**Pattern 2: Concurrent Operations with Dispatch Groups**

```swift
// ❌ GCD with DispatchGroup
let group = DispatchGroup()
var results: [Output] = []
let queue = DispatchQueue(label: "work", attributes: .concurrent)

for item in items {
    group.enter()
    queue.async {
        let result = processItem(item)
        results.append(result)
        group.leave()
    }
}
group.notify(queue: .main) {
    updateUI(results)
}

// ✅ Swift Concurrency with TaskGroup
Task {
    let results = await withTaskGroup(of: Output.self) { group in
        for item in items {
            group.addTask {
                await processItem(item)
            }
        }

        var collected: [Output] = []
        for await result in group {
            collected.append(result)
        }
        return collected
    }
    updateUI(results)
}
```

**Pattern 3: Limiting Concurrency**

```swift
// ❌ GCD with Semaphore (creates bottleneck)
let semaphore = DispatchSemaphore(value: 3)
for item in items {
    DispatchQueue.global().async {
        semaphore.wait()
        defer { semaphore.signal() }
        processItem(item)
    }
}

// ✅ Swift Concurrency with maxConcurrentTasks
let results = await withTaskGroup(of: Output.self) { group in
    var pending = items.makeIterator()
    var activeTasks = 0
    let maxConcurrency = 3

    // Fill initial batch
    while activeTasks < maxConcurrency, let item = pending.next() {
        group.addTask { await processItem(item) }
        activeTasks += 1
    }

    // As tasks complete, add more
    var collected: [Output] = []
    for await result in group {
        collected.append(result)
        if let item = pending.next() {
            group.addTask { await processItem(item) }
        }
    }
    return collected
}
```

---

## Code Review Checklist

When reviewing code for performance and concurrency best practices:

- [ ] `DispatchQueue.global().async` replaced with `Task` or async functions
- [ ] `DispatchQueue.main.async` removed in favor of `@MainActor`
- [ ] `DispatchSemaphore` replaced with async/await (never `wait()` inside a task)
- [ ] Manual `NSLock` + separate state replaced with an actor or `Mutex`
- [ ] CPU-heavy work moved off the main actor with `@concurrent` (not just wrapped in `Task {}`)
- [ ] `DispatchGroup` replaced with `withTaskGroup`
- [ ] No blocking code on main thread (no `.wait()`, semaphore blocks, locks)
- [ ] Thread exhaustion risks eliminated (using Swift Concurrency, not spawning many threads)
- [ ] Performance profiled to confirm efficiency improvements
