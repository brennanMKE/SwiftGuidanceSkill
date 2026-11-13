# SwiftUI Guidance Updates for Xcode 27

The SwiftUI references were re-validated in November 2026 against Xcode 27.2
(Swift 6.4.2, macOS 27.2 SDK). Each claim was checked three ways:

1. **SDK interfaces**: availability and deprecation annotations in the
   `SwiftUI`, `SwiftUICore`, and `Observation` `.swiftinterface` files.
2. **Apple documentation**: developer.apple.com reference pages.
3. **Running code**: small macOS programs that host views in `NSHostingView`
   and count `body` evaluations, initializer calls, observation callbacks, and
   transactions.

Files changed: `swift-guidance/references/ui.md` (rewritten),
`swift-guidance/references/swiftui-observation.md`, and `swift-guidance/SKILL.md`.

---

## Behavior that changed in Xcode 27

### `@State` is now a macro and evaluates its default value once

With the Xcode 27 SDK, `@State` resolves to a macro (`SwiftUIMacros.StateMacro`)
instead of the bare property wrapper. The expansion wraps the default value in a
closure:

```swift
// What `@State private var vm = ViewModel()` expands to (abridged)
private var __vm = SwiftUICore.State._makeStorage({
    ViewModel()
})
```

Measured result: a child view initialized 6 times by parent updates ran
`ViewModel.init` **once**. The result was the same for an `@Observable` class
and for a plain class. It also held with a macOS 14 deployment target, because
the macro expands at compile time.

The macro does not cover explicit initialization through the backing storage.
`_vm = State(initialValue: ViewModel())` inside a custom `init` still ran
`ViewModel.init` on all 6 view initializations.

Apple's `State` documentation hasn't been updated. It still says a `State`
property "always instantiates its default value when SwiftUI instantiates the
view" and recommends deferring creation with `.task`. That advice is still
correct for older toolchains and for custom `init`s.

**Guidance change:** keep `@State` defaults and view `init`s free of side
effects. Call out explicit `State(initialValue:)` in an `init` as the case that
still runs on every view init.

### `@Observable` skips equal-value writes

The `@Observable` macro now generates a `shouldNotifyObservers` member. It
appears in the macro's `names:` list in `Observation.swiftinterface`. Measured
behavior with `withObservationTracking`:

| Property type | Re-assigning the same value |
|---|---|
| `Equatable` (`Int`, `Double`, `String`, …) | no notification |
| Class reference, same instance | no notification |
| Class reference, new instance | notifies |
| Non-`Equatable` struct | notifies |

In a SwiftUI host, writing the same `Int` three times caused **0** `body`
re-evaluations.

**Guidance change:** the old rule ("every write notifies, equal-value writes
included") was removed. Store-level `guard x != newValue` is still recommended
when a mutator has side effects or stores a non-`Equatable` value. The dedupe
only suppresses same-value echoes. It does not stop loops between different
values.

> We could not test an older toolchain on this machine, so it is unknown which
> release introduced the dedupe. Don't assume it on older Xcode versions.

---

## Corrections to existing guidance

These were wrong before Xcode 27 as well.

| Old claim | Correction | Evidence |
|---|---|---|
| `.animation(_:value:)` "animates ALL state changes" | It animates only when `value` changes. The deprecated `.animation(_:)` is the one that animates everything. | Apple docs; a transaction probe showed `animation == nil` for unrelated changes |
| `List(items)` is index-based; add `id: \.id` | `List(items)` requires `Identifiable` and already uses `\.id`. Real anti-patterns: `indices` + `id: \.self`, regenerated `UUID()`s, `id: \.self` on non-unique values. | `List([1,2,3])` fails to compile without `Identifiable` |
| `onGeometryChange` requires iOS 17 | iOS 16 / macOS 13 / tvOS 16 / watchOS 9 (back-deployed) | `SwiftUICore.swiftinterface` |
| `GeometryReader` + `onAppear` is an acceptable fallback | `onAppear` fires once, so the size goes stale. Resizing 300 → 500 pt left it at 300; `onGeometryChange` reported 500. Use `onChange(of:initial:)` or `onGeometryChange`. | Running code |
| "Never use GeometryReader" | It's not deprecated. Prefer `onGeometryChange` for reading size; `containerRelativeFrame`, `visualEffect`, and `Layout` for layout; `GeometryReader` when nothing else fits. | SDK interfaces |
| `@Observable` is "thread-safe (compiler enforces access rules)" | It adds change tracking only. Isolation (`@MainActor`) is still required. | Language semantics |
| A child "recomputes even when [sibling] state changes" | SwiftUI skips a child's `body` when its inputs are unchanged. 5 sibling changes gave parent `body` ×5, child `body` ×0. | Running code |
| Cache expensive values via `onAppear` | Goes stale when inputs change. Use `.task(id:)` or compute in the model. | `onAppear` semantics |
| `@Observable` available with "Swift 5.9+" | Also requires iOS 17 / macOS 14 / tvOS 17 / watchOS 10 at runtime | `Observation.swiftinterface` |
| Theme example used `foregroundColor` | Deprecated; renamed to `foregroundStyle` | SDK interfaces |

---

## Confirmed unchanged

- On macOS, SwiftUI updates run inside AppKit's layout pass. An `onChange`
  stack trace included `NSHostingView.layout` → `_NSViewLayout`. The AppKit
  interop rules in `swiftui-observation.md` stand.
- `NavigationView` is deprecated in favor of `NavigationStack` /
  `NavigationSplitView`. It is soft-deprecated, so there is no compiler
  warning yet.
- `ObservableObject`, `@StateObject`, and `GeometryReader` are not deprecated.
- `@Entry` for environment values; `onChange` with a two- or zero-parameter
  closure (the one-parameter form is deprecated).
- The rules on which contexts may write observed state (`body`, view `init`,
  representable updates, `PreferenceKey.reduce`), and the ownership table
  (`@State` / plain property / `@Bindable` / `@Environment`).

---

## Re-running the checks

The probes are small Swift packages: one executable target, `NSHostingView` in
an offscreen `NSWindow`, and a run-loop pump between mutations. To re-validate
on a future Xcode:

- **Macro expansion:** build with
  `-Xswiftc -Xfrontend -Xswiftc -dump-macro-expansions` and inspect the
  `@State` and `@Observable` expansions.
- **Availability:** grep the SDK interfaces under
  `$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/SwiftUICore.framework`
  for `@available`, `deprecated`, and `_originallyDefinedIn`.
- **Runtime behavior:** count `init` and `body` calls across parent updates;
  use `withObservationTracking` for observation; use `.transaction { }`
  inside an `.animation(_:value:)` subtree to inspect animation scoping.
