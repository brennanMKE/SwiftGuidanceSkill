# SwiftUI + Observation State-Mutation Rules

Binding rules for code that writes `@Observable` / `@State` properties from
SwiftUI-driven code, and for anything that synchronizes model state with
AppKit (or UIKit). Load this reference before reviewing focus or selection
flow, before adding any write to a view-driven callback, and before "fixing" a
state-mutation warning.

These rules exist because violations produce *undefined behavior* — not a
compile error, but timing-dependent loops, dropped updates, broken input, and
AppKit NSExceptions that surface far from the offending line. The case study
at the bottom shows three distinct failures produced by one bug.

---

## Core Invariant

**View construction is pure, and every state change has an explicit owner.**

While SwiftUI is reconciling or laying out the view graph, no code may write
observed state that feeds the same graph. Writes belong to code with a clear
owner and trigger: event handlers (button actions, menu commands, NSEvent
monitors), delegate callbacks from outside the UI (network events, library
delegates), and genuinely asynchronous work.

The runtime warning "Modifying state during view update, this will cause
undefined behavior" is the *explicit* form of a violation. The implicit forms
have no warning: a write inside a synchronous call chain that *started* in the
update (see "AppKit Interop Hazards" below), or a write whose feedback loop
only manifests under specific timing.

---

## What Counts as SwiftUI-Driven Update Code

**Forbidden by default to write observed state from** (these run during
reconciliation/layout; any exception must be a documented architecture
decision, never a local workaround):

- `body`, and every computed property or helper it calls
- view `init`s (SwiftUI constructs views freely while diffing)
- `ViewModifier.body`
- `NSViewRepresentable.updateNSView` / `makeNSView` (and the
  `UIViewRepresentable` / controller variants), and their synchronous callees
- `PreferenceKey.reduce` and preference plumbing

```swift
// ❌ FORBIDDEN: write to observed state during view construction
struct PaneView: View {
    let model: PaneModel
    var body: some View {
        model.lastRendered = .now   // runs during reconciliation — undefined behavior
        return PaneContent(model: model)
    }
}
```

**Requires an audit, not a ban — `onChange`, `onAppear`, `onGeometryChange`:**
these actions run inside the update transaction, and writing state from them
is supported (SwiftUI schedules another pass). Whether a write is safe depends
on **what flipped the observed value**, not on the callback's name:

- *Event-origin flips are routine.* An `onChange(of: model.eventCount)`
  writing a UI tick is fine when the flip comes from an external event and the
  write doesn't feed back into anything that re-fires it.
- *Layout/focus/geometry-origin flips are the danger zone.* If the observed
  value was flipped synchronously by AppKit machinery — first-responder
  promotion, layout, geometry — the handler may be executing *inside that
  machinery* (mid-layout on macOS, see below), and a write there can crash.
  The audit: trace who flips the value, in what context, and what the write
  invalidates.

A bounded number of `onChange`-driven re-updates is tolerated by SwiftUI; the
runtime warning `"onChange(of:) action tried to update multiple times per
frame"` means an action is feeding back into its own trigger — treat it as a
loop, not noise.

---

## Ownership and Passing Rules for Observed State

| Situation | Use |
|---|---|
| View owns a reference-type `@Observable` model's lifetime | `@State private var` |
| View only reads an observable passed from a parent | plain property (`let` when possible) |
| View needs projected bindings into an observable (`$model.property`) | `@Bindable` |
| App-wide store/service | `@Environment` |
| Caches, delegates, closures, pending `Task`s, timers inside an `@Observable` type | `@ObservationIgnored` — implementation details must not invalidate views |
| Hot-path store mutators that callers may re-assert (e.g. `store.focus(id:)`) | make the API idempotent at the store (`guard x != newValue`) when the mutator has side effects beyond the assignment or stores a non-`Equatable` value type — never rely on call-site discipline |

Direct mutations of an observable model should normally live behind explicit
store/model methods. Use `@Bindable` in a view when SwiftUI needs the
projected binding, not just because the view has a reference to an observable.

`@State` stays `private`. Avoid `ObservableObject` / `@Published` /
`@StateObject` / `@ObservedObject` / `@EnvironmentObject` except when bridging
legacy or third-party code (see `ui.md`).

---

## Observation Semantics and Dependency Granularity

- **Equal-value writes are skipped — for some types.** On current
  toolchains (verified Swift 6.4 / Xcode 27.2) the `@Observable` macro
  generates `shouldNotifyObservers`, which suppresses the notification when
  the new value is the same:

  | Property type | Re-assigning the same value |
  |---|---|
  | `Equatable` (`Int`, `String`, `UUID?`, `Equatable` structs) | no notification (compared with `==`) |
  | Class reference | no notification if it's the same instance (`===`); a new instance always notifies |
  | Non-`Equatable` value type | **notifies** |

  So a bare `focusedPaneID = id` with an unchanged `UUID?` no longer
  invalidates views. A store-level guard is still the right shape when the
  mutator does more than assign — logging, AppKit calls, starting tasks — or
  stores a non-`Equatable` value, because those still run or notify on every
  re-assertion:

  ```swift
  // ✅ Idempotence lives at the store, not the call site
  @Observable
  final class AppStateStore {
      private(set) var focusedPaneID: UUID?
      func focusPane(id: UUID?) {
          guard focusedPaneID != id else { return }   // skips the side effects below
          focusedPaneID = id
          logger.debug("focus -> \(String(describing: id))")
          promoteFirstResponder(for: id)
      }
  }
  ```

  Dedupe only stops **same-value** echoes. Loops that ping-pong between
  *different* values (see the case study) are untouched by it.

- **Tracking is per property *read*.** A view depends on exactly what its
  body (and body's callees) read. Computed helpers broaden dependencies
  silently: a `isPaneFocused` helper that reads `tree.focusedPaneID` makes
  *every* pane view re-evaluate on *every* focus write. Pass narrow values
  down instead of whole observables when a child needs one fact.
- **Keep body-adjacent helpers pure and cheap.** No writes hidden inside
  formatters, accessors, or computed properties views call. A helper that
  logs once per item per body evaluation is the canary for a feedback loop
  (see Symptoms).
- **Loops form across layers, not inside one function.** The dangerous shape:
  model write → view update → AppKit side effect → observable flip → callback
  writes model. Each hop looks locally reasonable. Before adding a write to
  such a path, draw the full cycle and name what dead-ends it.

---

## AppKit Interop Hazards

On macOS, `NSHostingView` processes SwiftUI updates inside `-[NSView layout]`.
An `onChange` action can therefore be executing **inside AppKit's constraint
layout pass** (`_NSViewLayout`). Two hard rules follow:

1. **Never synchronously call constraint-dirtying or responder-changing
   AppKit APIs from SwiftUI-driven callbacks**: `makeFirstResponder`,
   `addSubview`, window operations, frame writes on Auto-Layout-managed
   views. Mid-pass, AppKit answers with an NSException
   (`_postWindowNeedsUpdateConstraints` inside `_NSViewLayout`) that
   `+[NSApplication _crashOnException:]` turns into `EXC_BREAKPOINT`.
2. **AppKit side effects flip `@Observable` properties synchronously.**
   `makeFirstResponder` → `becomeFirstResponder` → a focus delegate →
   `model.isFocused = true`. A handler observing that flip runs inside the
   promoter's context — the implicit core-invariant violation, with no
   runtime warning.

**Debugging:** the crash's faulting-thread stack shows only generic AppKit
display-cycle frames. The real chain lives in the *thrown exception's*
backtrace — `asiBacktraces` / `lastExceptionBacktrace` in the `.ips` crash
report. Read that first.

If a project needs an exception (e.g. a one-time `addSubview` on first mount,
or frame writes on a deliberately frame-based, non-Auto-Layout host view), it
must be bounded by design and documented in the project's architecture notes —
anything beyond that shape goes through an event handler or the store, not the
update.

---

## Two-Way Model ↔ AppKit Sync

When one fact lives in two places — *which pane is focused* might be both
`model.focusedPaneID` and `NSWindow.firstResponder` — every sync path must
declare a direction, and each direction gets exactly **one declared writer**:

- **Model-initiated** (keyboard command writes model → view reacts → AppKit
  follows): the follow-up into AppKit runs on a fresh main-actor turn, never
  inside the update transaction, and carries a staleness guard (generation
  token) so a superseded follow-up can never fire late.
- **AppKit-initiated** (user clicks): the code that *embodies the intent* —
  e.g. a click event monitor, during event dispatch — writes the model
  itself, synchronously. The interaction depends on winning that ordering.

**An observed property is evidence that something changed, not evidence of
intent.** Never reconstruct user intent from downstream observable effects —
libraries flip flags on *existing* objects as side effects of unrelated
operations (e.g. creating a new surface), so a model write keyed on such a
flip cannot tell a user action from churn. No context audit fixes a handler
whose trigger doesn't mean what it assumes. Route intent from its source as an
explicit command; Observation is for rendering, not for round-tripping
authority between two state holders.

The strongest dead end is therefore **no echo handler at all** — delete the
`observedFlag → model` write rather than guarding it. Where an echo handler
must exist, a store-level equality guard handles same-value echoes, and a
programmatic-change token / source check / staleness predicate handles
different-value ones — but guards damp the loop; removing the inference
removes it (equality-only guards and re-timing have both been verified to
fail).

Choose one authority per fact, write down the direction and single writer of
each path, and delete inferred echoes before reaching for guards.

---

## `Task` and Async Work

- A `Task` may write observed state when it represents **real asynchronous
  work** with clear ownership, cancellation, and stale-result checks (e.g.
  "is this tab still the focus target?" before acting).
- **`Task { @MainActor in … }` is not a safety device.** Hopping a write
  "later" moves it out of the current transaction but reorders it against
  every other queued main-actor job — retry ladders, echoes, user input.
  Deferring an echo write this way can silently break a user interaction
  (click-to-focus) that depended on winning the synchronous ordering.
- If a write is illegal where it happens, restructure **which code owns the
  write** (direction + echo suppression), not *when* it runs.

---

## Checklist Before Touching a State-Flow Path

1. List every property the change writes, and the exact context each write
   runs in (event handler? `onChange`? synchronous callee of an AppKit call?).
2. For each `onChange`/`onAppear` write: who flips the observed value, and in
   what context? Event-origin or layout/focus/geometry-origin? And does the
   flip *mean* what the handler assumes — can the library flip it as a side
   effect rather than as user intent?
3. List who observes each written property and what they do on invalidation.
   If any observer's reaction can write state, name the dead end.
4. For crashes, read `asiBacktraces` in the `.ips` before trusting the
   faulting-thread stack.
5. Verify with minimal targeted UI tests plus a manual pass of the affected
   pointer/keyboard behaviors. **Focus and click behavior cannot be signed
   off by compilation or unit tests.**

---

## Symptom → Cause Table

| Symptom | Likely cause |
|---------|--------------|
| Warning: "Modifying state during view update" | Direct write from `body` / view init / representable update / preference reduction |
| Warning: "onChange(of:) action tried to update multiple times per frame" | An `onChange` write feeds back into its own trigger (or another value in the same cycle) |
| Log spam: a body-adjacent helper's line cycling across all instances | Feedback loop, or a write invalidating far too broad a dependency graph |
| `EXC_BREAKPOINT` via `+[NSApplication _crashOnException:]`, all-AppKit stack with `_NSViewLayout` | Observable write or constraint-dirtying/responder AppKit call landed inside the layout pass — read `asiBacktraces` |
| Beachball / "app not idle" timeouts in UI tests | Same loop, pre-crash phase |
| A fix silences the warning but clicks / focus / keyboard input break | The write moved to the wrong owner or lost a race it used to win — restructure direction, don't re-time |
| Selection / focus reverts right after a programmatic UI change | Library churn flipped an observed flag on an untouched object and a handler treated it as intent — look for intent reconstructed from observable effects |

---

## Case Study: One Bug, Four Lessons

From a macOS terminal app syncing pane focus between an `@Observable` model
and `NSWindow.firstResponder`:

- **The crash:** a keyboard command wrote `focusedPaneID` (model-initiated);
  the view reacted by calling `makeFirstResponder` from `onChange` — inside
  the layout pass — and the echo handler wrote the model again mid-layout.
  NSException, `_crashOnException`. The decisive evidence was
  `asiBacktraces`, naming SwiftUI's `ObservationGraphMutation` →
  `_postWindowNeedsUpdateConstraints` chain.
- **The loop:** with two panes, stale focus-retry tasks re-promoted the old
  pane, so model and first responder ping-ponged between *different* values.
  A store-level idempotence guard alone did not stop it (verified: the crash
  reproduced with the guard in place).
- **The regression:** deferring the echo write into a `Task` stopped the
  crash but broke the AppKit-initiated direction — click-to-focus — because
  the deferred write lost the ordering it used to win synchronously. Timing
  fixes trade one undefined behavior for another.
- **The resolution:** a live trace showed the echo's trigger was never
  trustworthy — the terminal library flipped `isFocused` on existing surfaces
  whenever a new surface was created, so the handler reverted focus after
  *every* split, and the baseline only looked correct because a second echo
  healed it. The fix deleted the inference entirely (intent routed from the
  click monitor; promotion deferred + generation-guarded), and four click UI
  tests that had been failing for a week — dismissed as "environmental" —
  went green: they had been detecting this bug all along. Three analysis
  passes argued about write *context*; only tracing the trigger's *meaning*
  found the bug.

---

## Code Review Checklist

- [ ] No writes to observed state from `body`, view inits, `ViewModifier.body`, representable make/update, or `PreferenceKey.reduce`
- [ ] Every `onChange`/`onAppear` write audited by the *origin* of the flip (event vs layout/focus/geometry) and the *meaning* of the trigger
- [ ] Hot-path store mutators with side effects (or non-`Equatable` values) are idempotent at the store (`guard x != newValue`)
- [ ] Implementation details inside `@Observable` types (caches, tasks, delegates) marked `@ObservationIgnored`
- [ ] Children receive narrow values, not whole observables, when they need one fact
- [ ] No synchronous `makeFirstResponder` / `addSubview` / constraint-dirtying calls from SwiftUI-driven callbacks
- [ ] Each two-way-synced fact has one authority, a declared direction per path, and exactly one writer per direction
- [ ] No user intent reconstructed from downstream observable flips — intent routed from its source as an explicit command
- [ ] No `Task { @MainActor }` hops used to silence update-transaction violations
