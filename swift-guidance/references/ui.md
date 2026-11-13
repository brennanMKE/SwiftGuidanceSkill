# SwiftUI Best Practices

Claims in this file were verified against the Xcode 27.2 SDK (Swift 6.4) and
running code on macOS 27. Where behavior differs by toolchain, it says so.

---

## State Management

### Prefer @Observable over ObservableObject

`@Observable` requires iOS 17 / macOS 14 / tvOS 17 / watchOS 10 at runtime —
not just Swift 5.9. `ObservableObject` is not deprecated; prefer `@Observable`
for new code that can target those OS versions.

```swift
// ❌ AVOID (when targeting iOS 17+ / macOS 14+): Combine-based, manual @Published
import Combine

final class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
}

struct ContentView: View {
    @StateObject private var viewModel = UserViewModel()
    var body: some View { ... }
}
```

```swift
// ✅ PREFERRED: Observation macro, per-property dependency tracking
import Observation

@Observable
final class UserViewModel {
    var user: User?
    var isLoading = false

    func load() async { ... }
}

struct ContentView: View {
    @State private var viewModel = UserViewModel()
    var body: some View { ... }
}
```

**Why @Observable is better:**
- No Combine dependency and no `@Published` on every property
- Views depend only on the properties their `body` actually reads, so
  unrelated writes don't invalidate them
- Plain properties, `@Bindable`, and `@Environment(Model.self)` replace
  `@ObservedObject` / `@EnvironmentObject`

**`@Observable` is not thread-safe.** The macro adds change tracking, not
synchronization or `Sendable` conformance. Isolate the model (`@MainActor`,
explicitly or via MainActor-by-default) — see `actor-isolation.md`.

### `@State` with a reference-type default value

How often `@State private var model = Model()` evaluates `Model()` depends on
the toolchain:

- **Xcode 27 SDK and later:** `@State` is a macro that wraps the default value
  in a closure, so it is evaluated **once**, when SwiftUI first creates the
  view's storage — for any type, at any deployment target (it's a
  compile-time expansion). Verified: 6 view inits → 1 `Model.init`.
- **Older toolchains:** the default value is evaluated every time the view
  struct is initialized; the extra instances are discarded. Apple's `State`
  documentation still describes this behavior.
- **All toolchains:** assigning through the backing storage in a custom
  `init` — `_model = State(initialValue: Model())` — runs `Model()` on every
  view init. Verified: 6 view inits → 6 `Model.init`.

Keep `Model.init` free of side effects and expensive work either way. When the
model's init is heavy or depends on inputs, defer creation (Apple's
recommendation):

```swift
struct ContentView: View {
    @State private var library: Library?

    var body: some View {
        LibraryView(library: library)
            .task { library = Library() }
    }
}
```

---

## Geometry and Layout

### Prefer onGeometryChange for Reading Geometry

`GeometryReader` is not deprecated, but it is greedy (it takes all offered
space) and places its content at the top-leading corner, which often breaks
alignment when it's used just to *read* a size. Use `onGeometryChange` to
observe geometry without changing layout. It's available on
**iOS 16 / macOS 13 / tvOS 16 / watchOS 9** (back-deployed).

```swift
// ❌ AVOID: GeometryReader used only to read a size — it changes the layout
VStack {
    GeometryReader { geometry in
        Text("Width: \(geometry.size.width)")
    }
}
```

```swift
// ✅ PREFERRED: reads geometry, leaves layout untouched, updates on resize
struct MyView: View {
    @State private var width: CGFloat = 0

    var body: some View {
        Text("Width: \(width)")
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}
```

**Don't use `GeometryReader` + `onAppear` as a fallback.** `onAppear` fires
once, so the stored size goes stale on resize, rotation, or Dynamic Type
changes (verified: after resizing a window from 300 to 500 points wide, the
`onAppear` value stayed 300 and `onGeometryChange` reported 500). If you
read geometry from a background `GeometryReader`, observe the size:

```swift
.background {
    GeometryReader { proxy in
        Color.clear
            .onChange(of: proxy.size.width, initial: true) { _, newWidth in
                width = newWidth
            }
    }
}
```

### When GeometryReader (or an alternative) is the right tool

Reading a size and then storing it in `@State` to drive layout costs an extra
layout pass and can oscillate. When the container size should *determine*
layout, use a layout API instead:

| Need | Use |
|---|---|
| Size a view as a fraction of its scroll view / container | `containerRelativeFrame` (iOS 17+) |
| Position- or size-based visual effects (scale, opacity, offset) without changing layout | `visualEffect` (iOS 17+) |
| Custom arrangement of children based on proposed size | the `Layout` protocol (iOS 16+) |
| Children laid out from the container's size, nothing else fits | `GeometryReader` — acceptable |

---

## View Hierarchy and Recomputations

### Keep Body Dependencies Narrow

SwiftUI re-runs a view's `body` when state it read changes. It then compares
each child view's stored inputs and skips a child's `body` when they're
unchanged. So a sibling's state change re-runs the **parent's** `body`, not
every child's (verified: 5 sibling-state changes → parent `body` ×5,
unchanged child `body` ×0).

What actually causes excess work:
- A large `body` that reads many pieces of state, so every change rebuilds a
  big subtree
- Passing whole models or closures to children, so their inputs always look
  changed
- Reading `@Observable` properties in a parent only to forward them

```swift
// ❌ PROBLEM: one large body reads both values; every animation tick
// rebuilds the whole VStack, including the list
struct ContentView: View {
    @State private var selectedUser: User?
    @State private var animationValue: Double = 0

    var body: some View {
        VStack {
            UserList(selection: $selectedUser)
            if let selectedUser {
                UserDetail(user: selectedUser)
            }
            AnimatedView(value: $animationValue)
        }
    }
}

// ✅ SOLUTION: move independent state into the subview that uses it
struct ContentView: View {
    var body: some View {
        VStack {
            UserListContainer()
            AnimationContainer()
        }
    }
}

struct UserListContainer: View {
    @State private var selectedUser: User?
    var body: some View {
        VStack {
            UserList(selection: $selectedUser)
            if let selectedUser {
                UserDetail(user: selectedUser)
            }
        }
    }
}

struct AnimationContainer: View {
    @State private var animationValue: Double = 0
    var body: some View {
        AnimatedView(value: $animationValue)
    }
}
```

---

## List and ForEach Identity

### Use stable, unique identity

`List(items)` and `ForEach(items)` require `Identifiable` elements and already
use `\.id` — they are **not** index-based, and adding `id: \.id` changes
nothing. The real problems are identity that is unstable or not unique:

```swift
// ❌ AVOID: index identity — inserts/deletes shift every row's identity,
// breaking animations and per-row @State
ForEach(items.indices, id: \.self) { index in
    ItemRow(item: items[index])
}

// ❌ AVOID: id: \.self on values that may repeat (duplicate IDs are undefined behavior)
ForEach(names, id: \.self) { name in
    Text(name)
}

// ❌ AVOID: identity regenerated on every load
struct Item: Identifiable {
    let id = UUID()   // new IDs each time the array is rebuilt from the same data
    let name: String
}

// ✅ PREFERRED: Identifiable elements with an ID from the data source
struct Item: Identifiable {
    let id: Item.ID   // database/server ID, stable across reloads
    let name: String
}

List(items) { item in
    ItemRow(item: item)
}

// ✅ When the type isn't Identifiable, pass a stable unique key path
ForEach(records, id: \.serverID) { record in
    RecordRow(record: record)
}
```

### Lazy Loading

```swift
// ✅ Lazy stacks create rows on demand
ScrollView {
    LazyVStack(spacing: 0) {
        ForEach(items) { item in
            ItemRow(item: item)
                .onAppear {
                    if item.id == items.last?.id {
                        viewModel.loadMore()
                    }
                }
        }
    }
}
```

---

## Styling and Theming

### Use @Environment for Theme Access

```swift
struct AppTheme {
    let primaryColor: Color
    let secondaryColor: Color
}

// ✅ @Entry generates the EnvironmentKey boilerplate
extension EnvironmentValues {
    @Entry var appTheme = AppTheme(primaryColor: .blue, secondaryColor: .gray)
}

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appTheme, AppTheme(primaryColor: .blue, secondaryColor: .gray))
        }
    }
}

struct ContentView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("Title")
            .foregroundStyle(theme.primaryColor)   // foregroundColor(_:) is deprecated
    }
}
```

---

## Animation

### Scope animations to a value or a specific change

`.animation(_:value:)` animates only when `value` changes — other state
changes in the same subtree are not animated (verified with a transaction
probe). The modifier that animates *every* change is the deprecated
`.animation(_:)` without `value:`.

```swift
// ❌ AVOID: deprecated — animates any change in the subtree
VStack { ... }
    .animation(.easeInOut)

// ✅ GOOD: animates only when isExpanded changes
struct ExpandableView: View {
    @State private var isExpanded = false

    var body: some View {
        VStack {
            Text("Content")
            if isExpanded {
                Text("Details")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: isExpanded)
        .onTapGesture { isExpanded.toggle() }
    }
}

// ✅ ALSO GOOD: animate one specific state change at its source
Button("Toggle") {
    withAnimation(.easeInOut) {
        isExpanded.toggle()
    }
}
```

Use `.animation(_:value:)` when every change to a value should animate,
regardless of who changes it. Use `withAnimation` when only a particular
action should animate.

---

## Expensive Work in View Body

`body` runs often; keep it cheap and side-effect free. Don't cache derived
values via `onAppear` — it runs once, so the cache goes stale when inputs
change.

```swift
// ❌ PROBLEM: expensive work on every body evaluation
struct ReportView: View {
    let records: [Record]
    var body: some View {
        Text(summarize(records))
    }
}

// ❌ ALSO WRONG: cached once, never refreshed when `records` changes
Text(cachedSummary ?? "")
    .onAppear { cachedSummary = summarize(records) }

// ✅ SOLUTION: recompute when the input changes (async work, cancellation included)
struct ReportView: View {
    let records: [Record]
    @State private var summary = ""

    var body: some View {
        Text(summary)
            .task(id: records) {
                summary = await summarizeInBackground(records)
            }
    }
}
```

When the derived value belongs to the model, compute it there (a stored
property updated on mutation) instead of in the view.

---

## Navigation

### Use NavigationStack / NavigationSplitView instead of NavigationView

`NavigationView` is deprecated (the SDK points to `NavigationStack` or
`NavigationSplitView`; iOS 16 / macOS 13+).

```swift
// ❌ AVOID: deprecated NavigationView with destination-based links
NavigationView {
    List(items) { item in
        NavigationLink(destination: DetailView(item: item)) {
            Text(item.name)
        }
    }
}

// ✅ PREFERRED: NavigationStack with value-based links
struct ListView: View {
    @State private var path: [Item] = []
    let items: [Item]

    var body: some View {
        NavigationStack(path: $path) {
            List(items) { item in
                NavigationLink(value: item) {
                    Text(item.name)
                }
            }
            .navigationDestination(for: Item.self) { item in
                DetailView(item: item)
            }
        }
    }
}
```

---

## Common Pitfalls

| Pitfall | Problem | Solution |
|---------|---------|----------|
| `ForEach(items.indices, id: \.self)` | Identity shifts on insert/delete | Iterate `Identifiable` elements |
| `id: \.self` on values that can repeat | Duplicate IDs → undefined behavior | Use a unique, stable key path |
| `let id = UUID()` on rebuilt models | New identity every reload; rows reset | Use the data source's ID |
| Side effects or heavy work in a `@State` default or view `init` | Runs per view init on older toolchains and in custom inits | Keep inits cheap; defer with `.task` |
| `.animation(_:)` without `value:` | Deprecated; animates every change | `.animation(_:value:)` or `withAnimation` |
| `GeometryReader` only to read a size | Greedy, top-leading layout | `onGeometryChange` |
| `GeometryReader` + `onAppear` to capture size | Value goes stale on resize | `onGeometryChange` or `onChange(of:initial:)` |
| Caching derived data via `onAppear` | Never refreshes | `.task(id:)` or compute in the model |
| `ObservableObject` + `@StateObject` in iOS 17+ code | Combine boilerplate, coarse invalidation | `@Observable` + `@State` |
| `foregroundColor(_:)` | Deprecated | `foregroundStyle(_:)` |

---

## Code Review Checklist

- [ ] New models use `@Observable` when the deployment target is iOS 17 / macOS 14+
- [ ] `@Observable` models are isolated (`@MainActor` or MainActor-by-default) — the macro adds no thread safety
- [ ] `@State` default values and view `init`s do no side effects or heavy work
- [ ] Geometry is read with `onGeometryChange`; `GeometryReader` is used only when it drives layout and no layout API fits
- [ ] `NavigationStack` / `NavigationSplitView` instead of deprecated `NavigationView`
- [ ] `List` / `ForEach` identity is stable and unique (no indices, no regenerated UUIDs)
- [ ] Independent state lives in the smallest view that uses it
- [ ] No expensive work in `body`; derived data refreshes with its inputs (`.task(id:)` or model)
- [ ] Animations are scoped with `.animation(_:value:)` or `withAnimation`
- [ ] Theme/configuration accessed via `@Environment` (`@Entry`)
