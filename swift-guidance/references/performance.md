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

### NSLock and Synchronization — Bottlenecks Under Contention

**Problem**: Locks serialize access and cause threads to block:

```swift
// ❌ AVOID: Explicit locking
let lock = NSLock()
var cachedData: [String: Any] = [:]

func getData(key: String) -> Any? {
    lock.lock()
    defer { lock.unlock() }
    return cachedData[key]
}
```

**Why this is problematic**:
- Lock contention causes threads to block waiting for acquisition
- Blocking threads consume memory and system resources
- Difficult to reason about — deadlocks possible with multiple locks
- Context switches add latency
- Can trigger priority inversion (low-priority thread blocking high-priority work)

**Solution**: Use actors for thread-safe access:

```swift
// ✅ PREFERRED: Actor with isolated state
actor DataCache {
    private var cachedData: [String: Any] = [:]

    func getData(key: String) -> Any? {
        return cachedData[key]
    }

    func setData(_ value: Any, for key: String) {
        cachedData[key] = value
    }
}

// Usage (non-blocking)
let cache = DataCache()
let value = await cache.getData(key: "user")
```

**Actor advantages**:
- Compiler-enforced thread safety (no manual locking)
- Non-blocking — caller is suspended, not blocked
- Automatic serialization without lock contention
- Integrates with async/await

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
5. **Difficult Cancellation**: No built-in cancellation mechanism like `CancellationToken`

### Solution: Swift Concurrency with Tasks and Structured Concurrency

```swift
// ✅ PREFERRED: Swift concurrency
func loadData() async {
    let data = await fetchData()  // Suspends, doesn't block
    updateUI(data)  // Resumes on main thread
}

// Call it:
Task {
    await loadData()
}
```

**Benefits**:
- **Unified Executor Model**: Automatic thread pool management
- **No Thread Exhaustion**: Tasks are lightweight, not tied to threads
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

// ✅ Swift Concurrency
Task {
    let result = await expensiveComputation()
    updateUI(result)  // Implicitly on main (if called from @MainActor context)
}
```

**Pattern 2: Concurrent Operations with Dispatch Groups**

```swift
// ❌ GCD with DispatchGroup
let group = DispatchGroup()
var results: [Result] = []
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
    let results = await withTaskGroup(of: Result.self) { group in
        for item in items {
            group.addTask {
                await processItem(item)
            }
        }

        var collected: [Result] = []
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
let results = await withTaskGroup(of: Result.self) { group in
    var pending = items.makeIterator()
    var activeTasks = 0
    let maxConcurrency = 3

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
        }
    }
    return collected
}
```

---

## Migration Checklist

When converting from GCD to Swift Concurrency:

- [ ] Replace `DispatchQueue.global().async` with `Task` or async functions
- [ ] Remove `DispatchQueue.main.async` — use `@MainActor` instead
- [ ] Replace `DispatchSemaphore` with actors or async/await
- [ ] Replace `NSLock` with actors
- [ ] Replace `DispatchGroup` with `withTaskGroup`
- [ ] Test for thread exhaustion improvements (should see fewer total threads)
- [ ] Profile to confirm CPU usage improvement (fewer context switches)
