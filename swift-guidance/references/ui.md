# SwiftUI Best Practices

---

## State Management

### Use @Observable instead of ObservableObject

**Problem with ObservableObject:**
```swift
// ❌ AVOID: Legacy pattern, Combine dependency, manual tracking
import Combine

class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false

    func load() {
        // Manual work tracking
    }
}

// Usage requires @StateObject in view
struct ContentView: View {
    @StateObject var viewModel = UserViewModel()
    var body: some View { ... }
}
```

**Solution with @Observable:**
```swift
// ✅ PREFERRED: Modern macro, no Combine, automatic tracking
import Observation

@Observable
final class UserViewModel {
    var user: User?
    var isLoading = false

    func load() async {
        // No manual tracking needed
    }
}

// Usage is simpler
struct ContentView: View {
    @State private var viewModel = UserViewModel()
    var body: some View { ... }
}
```

**Why @Observable is better:**
- No Combine dependency
- Automatic property tracking (no @Published)
- Works seamlessly with async/await
- Thread-safe (compiler enforces access rules)
- No need for @StateObject or @EnvironmentObject boilerplate

---

## Geometry and Layout

### Never use GeometryReader — Use onGeometryChange Instead

**Problem with GeometryReader:**
```swift
// ❌ AVOID: GeometryReader disrupts alignment
struct MyView: View {
    var body: some View {
        VStack {
            GeometryReader { geometry in
                Text("Width: \(geometry.size.width)")
                    // This view doesn't participate in normal layout
                    // Causes alignment issues, forces size constraints
            }
        }
    }
}
```

**Solution with onGeometryChange (iOS 17+):**
```swift
// ✅ PREFERRED: Non-blocking geometry access
struct MyView: View {
    @State private var width: CGFloat = 0

    var body: some View {
        VStack {
            Text("Width: \(width)")
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { newWidth in
                    width = newWidth
                }
        }
    }
}
```

**Why onGeometryChange is better:**
- Doesn't disrupt view hierarchy
- Doesn't force layout constraints
- Natural side-effect handling
- Clearer intent and control flow

**For older iOS (< 17), use a workaround:**
```swift
// ✅ ACCEPTABLE FALLBACK
struct MyView: View {
    @State private var width: CGFloat = 0

    var body: some View {
        VStack {
            Text("Width: \(width)")
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                width = geometry.size.width
                            }
                    }
                )
        }
    }
}
```

---

## View Hierarchy and Recomputations

### Extract State Management to Reduce Recomputations

```swift
// ❌ PROBLEM: Large view recomputes when unrelated state changes
struct ContentView: View {
    @State private var selectedUser: User?
    @State private var animationValue: Double = 0

    var body: some View {
        VStack {
            UserList(selection: $selectedUser)
            if let user = selectedUser {
                UserDetail(user: user)  // Recomputes even when animation changes
            }
            AnimatedView(value: $animationValue)
        }
    }
}

// ✅ SOLUTION: Extract independent state to separate views
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
            if let user = selectedUser {
                UserDetail(user: user)
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

## List and ScrollView Performance

### Use ID in List and ForEach

```swift
// ❌ AVOID: Index-based identification (entire list recomputes on changes)
List(items) { item in
    ItemRow(item: item)
}

// ✅ PREFERRED: Stable ID (only changed items recompute)
List(items, id: \.id) { item in
    ItemRow(item: item)
}
```

### Lazy Loading and Virtualization

```swift
// ✅ Lazy evaluation for large lists
LazyVStack(spacing: 0) {
    ForEach(items, id: \.id) { item in
        ItemRow(item: item)
            .onAppear {
                // Load more if near bottom
                if item == items.last {
                    viewModel.loadMore()
                }
            }
    }
}
```

---

## Styling and Theming

### Use @Environment for Theme Access

```swift
// ✅ Define theme model
struct AppTheme {
    let primaryColor: Color
    let secondaryColor: Color
}

// ✅ Define environment key
extension EnvironmentValues {
    @Entry var appTheme = AppTheme(primaryColor: .blue, secondaryColor: .gray)
}

// ✅ Set theme at app level
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appTheme, AppTheme(primaryColor: .blue, secondaryColor: .gray))
        }
    }
}

// ✅ Access theme in views
struct ContentView: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack {
            Text("Title")
                .foregroundColor(theme.primaryColor)
        }
    }
}
```

---

## Animation Best Practices

### Use .animation() Modifier Correctly

```swift
// ❌ PROBLEM: Animates ALL state changes
struct ExpandableView: View {
    @State private var isExpanded = false

    var body: some View {
        VStack {
            Text("Content")
            if isExpanded {
                Text("Details")
            }
        }
        .animation(.easeInOut, value: isExpanded)  // Animates all changes
    }
}

// ✅ PREFERRED: Animate specific changes with withAnimation
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
        .onTapGesture {
            withAnimation(.easeInOut) {
                isExpanded.toggle()
            }
        }
    }
}
```

### Avoid Expensive Computations in View Body

```swift
// ❌ PROBLEM: Expensive operation every render
struct MyView: View {
    var body: some View {
        VStack {
            Text(expensiveStringComputation())
        }
    }
}

// ✅ SOLUTION: Cache or compute once
struct MyView: View {
    @State private var cachedString: String?

    var body: some View {
        VStack {
            Text(cachedString ?? "")
                .onAppear {
                    cachedString = expensiveStringComputation()
                }
        }
    }
}
```

---

## Navigation

### Avoid NavigationView — Use NavigationStack (iOS 16+)

```swift
// ❌ AVOID: Deprecated NavigationView
NavigationView {
    List(items) { item in
        NavigationLink(destination: DetailView(item: item)) {
            Text(item.name)
        }
    }
}

// ✅ PREFERRED: NavigationStack with data binding
struct ListView: View {
    @State private var navigationPath: [Item] = []
    let items: [Item]

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
| Using `.id()` on mutable objects | Identity unstable | Use stable identifier property |
| ForEach without `id` parameter | Entire list recomputes | Add `id: \.id` or similar |
| Expensive view initializers | View created repeatedly | Move expensive logic to `.onAppear` |
| Nested @State | State conflicts and bugs | Lift state to parent or use @Observable |
| ObservableObject + @StateObject | Boilerplate and Combine dependency | Use @Observable instead |
| GeometryReader for alignment | Disrupts layout | Use `onGeometryChange()` |

---

## Code Review Checklist

- [ ] State management uses `@Observable` instead of ObservableObject
- [ ] Layout code uses `onGeometryChange()` instead of GeometryReader
- [ ] Navigation uses NavigationStack instead of deprecated NavigationView
- [ ] List and ForEach have stable IDs defined
- [ ] State management is extracted to minimize view recomputations
- [ ] Expensive computations cached and not run in view body
- [ ] Theme/configuration accessed via `@Environment`
- [ ] View hierarchy optimized (no unnecessary nested state)
