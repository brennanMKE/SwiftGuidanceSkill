---
name: swift-guidance
description: Review Swift code for correctness and modern API usage. Trigger when users ask to review Swift files, report concurrency issues (DispatchQueue vs async/await), thread safety problems, logging gaps, SwiftUI anti-patterns, "Modifying state during view update" warnings, Observation feedback loops, focus/selection bugs or AppKit-interop crashes, dark mode / preview issues, performance issues, multiplatform setup problems, or project/package build-setting configuration (MainActor default isolation, strict concurrency). Load relevant references based on the issue domain—concurrency, logging, actor isolation, project configuration, UI, observation state-mutation rules, dark mode, performance, or multiplatform configuration.
license: MIT
metadata:
  author: Brennan Stehling
  version: "1.0"
---

Review Swift code for correctness, modern API usage, and adherence to best practices. Report only genuine problems that impact safety, maintainability, or performance—do not nitpick style.

## CRITICAL: When to STOP Reporting

**This is the most important rule. Follow it strictly.**

STOP reporting issues immediately when you have identified and explained:
- **Scoped review**: The 1 main issue the user asked about + brief note that deeper review exists
- **Full review**: 1-2 high-impact issues per topic area maximum

**Do NOT continue looking for more issues** once you meet these conditions.

**Examples:**
- User: "My DispatchQueue code doesn't work" → Find the DispatchQueue issue, explain fix, STOP
- User: "Review my DataManager" → Find 1-2 main issues (e.g., print() → os.log, @MainActor), STOP
- User: "Any anti-patterns in this SwiftUI view?" → Find 1-2 main anti-patterns, STOP

**If you find multiple issues, report ONLY the most impactful ones and STOP.**

---

## How to Use This Skill

This skill is designed to review Swift code and provide targeted guidance. Use it when:
- **User asks for a code review** of Swift files (e.g., "review this viewmodel")
- **User reports a problem** (e.g., "my DispatchQueue code doesn't work right")
- **User asks about a specific area** (e.g., "how do I properly use @MainActor?")
- **You see deprecated patterns** in Swift code being discussed

## Core Instructions

Follow these modern Swift best practices:

- **Concurrency**: Always use Swift Concurrency (async/await, Task, actors) instead of DispatchQueue, Combine callbacks, or completion handlers. In Swift 6+, use `@concurrent` to explicitly run work off-actor; understand that `nonisolated async` inherits the caller's isolation by default.
- **Logging**: Use Apple's unified logging (`os.log`) with file-scoped loggers, never `print()` for debugging in production code.
- **Project Configuration**: Enable MainActor-by-default isolation and complete strict concurrency. Xcode: `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_STRICT_CONCURRENCY = complete`. Swift packages (tools version 6.2+): a shared `swiftSettings` with `.enableUpcomingFeature("StrictConcurrency")` and `.defaultIsolation(MainActor.self)` applied to every target.
- **Thread Safety**: Properly annotate types with `nonisolated` or `@MainActor` in MainActor-by-default projects. Flag UI updates that happen off the main thread.
- **SwiftUI**: Use `@Observable` macro instead of `ObservableObject`. Avoid `GeometryReader` when `onGeometryChange()` works instead.
- **Observation state-mutation rules**: View construction is pure — never write observed state from `body`, view inits, representable make/update, or `PreferenceKey.reduce`. Audit `onChange`/`onAppear` writes by what flipped the observed value (event-origin is routine; layout/focus/geometry-origin can be executing inside AppKit's layout pass). One authority per two-way-synced fact, one writer per direction; never reconstruct user intent from downstream observable flips. `Task { @MainActor }` is not a fix for an update-transaction violation — restructure who owns the write, not when it runs.
- **Dark Mode**: Use `.environment(\.colorScheme, …)` (subtree-scoped) for side-by-side previews; `.preferredColorScheme` propagates to the entire window. Use `.background(.background)` instead of UIKit-only `Color(.systemBackground)`. Custom colors must be adaptive (asset catalog or `Color(light:dark:)`).
- **Multiplatform**: Use SDK-specific build settings (`[sdk=iphone*]` and `[sdk=macos*]`) when supporting multiple platforms to prevent platform-specific defaults from leaking.
- **Modules & Imports**: Under Swift 6.0+ (SE-0409), mark imports `public` only when the dependency's types appear in your module's public API; prefer `internal import` for implementation-detail dependencies. Under Swift 6.1+ (SE-0444), every extension member, operator, or conformance you use must come from a directly-imported module — not a transitive one. Avoid `@_implementationOnly`.
- **Performance**: Prioritize efficient resource usage and minimize unnecessary allocations.

## Guidance Process

### Step 1: Understand the Scope

First, determine what kind of review this is:

- **Scoped review**: User reports a specific problem (concurrency, logging, SwiftUI patterns, etc.)
  → Load only the relevant reference file(s)
  → Find the first major issue in that area and fix it
  → Note that deeper review may be needed

- **Full code review**: User asks for general review without specifics
  → Load references in priority order (see step 2)
  → Stop after finding 1-2 high-impact issues per area
  → Provide a prioritized summary

### Step 2: Load Relevant References (As Needed)

Only load references that apply to the code or the user's question:

| Issue Domain | Reference File | When to Load |
|--------------|---|---|
| DispatchQueue, Combine, completion handlers | `references/concurrency.md` | Code uses old patterns OR user asks about async code |
| print() debugging, logging setup | `references/logging.md` | Code uses `print()` OR user asks about debugging/observability |
| Build settings, default isolation, strict concurrency setup | `references/project-configuration.md` | Reviewing an Xcode project / `Package.swift` for concurrency settings OR user asks how to enable MainActor-by-default or strict concurrency |
| @MainActor, actor isolation, thread safety | `references/actor-isolation.md` | Code has thread-safety concerns OR MainActor-by-default warnings |
| `nonisolated async`, `@concurrent` isolation | `references/nonisolated-concurrent.md` | Code uses `nonisolated async` OR needs `@concurrent` for off-actor work, or has Swift 6 isolation issues |
| SwiftUI patterns, state management | `references/ui.md` | Code uses SwiftUI AND has ObservableObject, GeometryReader, or state issues |
| Observed-state writes during view updates, Observation feedback loops, model ↔ AppKit sync | `references/swiftui-observation.md` | "Modifying state during view update" / "tried to update multiple times per frame" warnings, `EXC_BREAKPOINT` in `_NSViewLayout`, focus/selection bugs, writes inside `onChange`/`body`/representable updates, OR user is adding state writes to view-driven callbacks |
| Light/dark mode, SwiftUI previews, adaptive colors | `references/dark-mode.md` | Code defines `#Preview` with multiple color schemes, uses `.preferredColorScheme` / `Color(.systemBackground)` / hardcoded `.white` / `.black`, OR user asks about dark mode support |
| Memory, CPU, disk usage | `references/performance.md` | Code has performance concerns OR user asks about optimization |
| iOS + macOS setup, letterboxing | `references/multiplatform.md` | Project supports multiple platforms AND has build/layout issues |
| Implicit return in functions/expressions | `references/implicit-return.md` | Code has explicit `return` statements that could be implicit OR user asks about modern Swift style |
| Executable entry points, `@main`, file naming | `references/executables.md` | Code defines an executable target OR user asks about entry points or `main.swift` naming |
| `public import` errors, "not imported publicly", "requires import of module", transitive extension members, `@_implementationOnly` | `references/transitive-dependencies.md` | Code shows SE-0409 / SE-0444 build errors, project is migrating to Swift 6.0 / 6.1, OR user asks about module access levels or transitive imports |

**Example:** User asks "how do I migrate from ObservableObject?" → Load only `references/ui.md`.

**Example:** Code review shows several functions with explicit returns when implicit would be cleaner → Load `references/implicit-return.md` for style guidance.

### Step 3: Classify Issues by Severity

Before reporting, classify each issue. **Then apply the stopping rule.**

**CRITICAL (always report if found):**
- DispatchQueue/Combine used instead of async/await for new code
- `print()` used instead of `os.log` for anything beyond local debugging
- UI code running off the main thread without `@MainActor` protection
- MainActor violations in MainActor-by-default projects (compilation errors waiting to happen)
- Writes to observed state from `body`, view inits, representable make/update, or `PreferenceKey.reduce` (undefined behavior, even without the runtime warning)
- Synchronous responder-changing or constraint-dirtying AppKit calls (`makeFirstResponder`, `addSubview`, frame writes) from SwiftUI-driven callbacks — these crash inside the layout pass
- User intent reconstructed from a downstream observable flip (echo handlers that round-trip authority between model and AppKit)

**Report the CRITICAL issues, then STOP if you've hit 1-2 per area.**

---

**HIGH (report 1-2 per area, then stop):**
- `GeometryReader` when `onGeometryChange()` would work
- `ObservableObject` when `@Observable` is available (Swift 5.9+)
- Immutable value types marked `@MainActor` (should be `nonisolated`)
- Missing `@MainActor` on UI-bound code in MainActor-by-default projects
- `nonisolated async` functions that should use `@concurrent` to explicitly run off-actor (Swift 6+)
- Incorrect use of `@concurrent` in Swift 6+ (combining with `@MainActor`, or accessing actor-isolated state)
- `Task { @MainActor }` hops used to silence an update-transaction violation instead of restructuring write ownership
- Non-idempotent hot-path store mutators (`@Observable` re-notifies on equal-value writes; guard at the store)
- Implementation details inside `@Observable` types (caches, pending Tasks, delegates) not marked `@ObservationIgnored`

**Report HIGH issues if no CRITICAL exist in that area, but STOP after 1-2.**

---

**MEDIUM (skip unless scoped review specifically asks for deep dive):**
- Missing structured logging (`os.log`) where it would help debugging
- Inefficient state tracking in SwiftUI
- Unused actors or thread-safety mechanisms
- Explicit returns that could be implicit in single-expression functions/expressions

**Do NOT report MEDIUM issues in standard reviews.**

**OPTIONAL STYLE GUIDANCE (mention in summary if relevant, but don't prioritize over correctness):**
- Implicit return for improved readability and modern Swift style

**Note:** Only mention style guidance if you've already reported CRITICAL and HIGH issues. Prioritize correctness over style.

---

**NICE-TO-HAVE (never report):**
- Minor performance optimizations
- Code style or naming conventions
- Warnings that don't affect runtime behavior

**Never report NICE-TO-HAVE issues. Ever.**

### Step 4: Format Your Response

For each issue found:

1. **State the file and line(s)** — e.g., "UserViewModel.swift, lines 42–51"
2. **Name the rule** — e.g., "Use async/await instead of DispatchQueue"
3. **Show before/after code** — Make the fix concrete and copy-paste ready
4. **Explain why** — One sentence on why this matters (safety, maintainability, clarity)

**Example:**
```
**UserViewModel.swift, Lines 18–25: Use async/await instead of DispatchQueue**

Before:
DispatchQueue.global().async {
    URLSession.shared.dataTask(with: url) { data, _, error in
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }.resume()
}

After:
func loadUser() async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}

Why: async/await is clearer, safer (no retain cycles), and type-checked by the compiler.
```

### Step 5: End with a Summary

**If issues found:**
```
## Summary (Prioritized)

1. **Concurrency (CRITICAL):** Replace DispatchQueue with async/await on lines 18–51.
2. **Logging (HIGH):** Replace print() with os.log on lines 67–72.
3. Note: Further review of [area] recommended.
```

**If no issues found:**
```
## Summary

This code follows Swift best practices for [areas reviewed]. No critical issues found. 
Well done!
```

## When to Stop Reviewing

**These are hard stops. Do not bypass them.**

### Scoped Review (User Reports One Specific Problem)

User says: "My DispatchQueue doesn't work" or "Why is my print() not showing?"

**Action:**
1. Find that ONE issue
2. Provide the fix with before/after code and explanation
3. **STOP immediately** — do not look for other issues
4. Add: "Note: Further review of [area] recommended if needed."

**Do NOT:**
- Keep searching for more problems
- Report secondary issues (e.g., user asked about DispatchQueue, don't report ObservableObject)
- Overwhelm with additional fixes

### Full Code Review (User Asks "Review My Code")

User says: "Review my ViewController" or "Any issues with this file?"

**Action:**
1. Load only relevant references
2. Find 1–2 high-impact issues per area (concurrency, logging, UI, etc.)
3. **STOP after 1–2 per area** — do not report more
4. Report only CRITICAL and HIGH severity; skip MEDIUM/NICE-TO-HAVE

**Do NOT:**
- Report 5–10 issues
- Report every issue you find
- Report NICE-TO-HAVE items in the same list as CRITICAL

### Code is Clean

If no CRITICAL or HIGH issues exist:

**Say explicitly:**
```
This code follows Swift best practices for [areas reviewed].
No critical issues found. Well done!
```

**Do NOT:** Say nothing or give it a low score.

## Common Pitfalls (Don't Do These)

❌ **CRITICAL PITFALLS — Violate the stopping rule:**
- Reporting 5+ issues when user asked about 1 problem
- Continuing to search for issues after you've found 1-2 per area
- Reporting MEDIUM/NICE-TO-HAVE items in a scoped review
- Treating "find all issues" as the goal (it's not; stopping is the goal)

❌ **Don't report:**
- Trivial naming preferences (e.g., "userId" vs "userID")
- Comments that could be code (if the code is clear)
- Micro-optimizations that don't affect measurable performance
- Issues beyond the 1-2 per area limit, no matter how valid they are

❌ **Don't assume:**
- The project uses Swift 6 or MainActor-by-default (ask or infer from code)
- The user needs all 6 areas reviewed (scope to what matters)
- Completion handlers are always wrong (sometimes necessary for callbacks that live outside async contexts)

✅ **Do:**
- **STOP after 1-2 issues per area** — this is your primary goal
- Explain the "why" behind each recommendation
- Provide copy-paste ready examples
- Say "well done" if code is clean
- Ask for clarification if the issue context is unclear

✅ **If you find 5+ issues:**
- Pick the 1-2 most impactful
- Report only those
- Note: "Further review of [area] recommended separately"

## References

Load these as needed (see Step 2 above):

- `references/concurrency.md` — Modern Swift Concurrency patterns, avoiding DispatchQueue and Combine
- `references/logging.md` — Structured logging with `os.log` and proper setup
- `references/project-configuration.md` — Xcode and Swift package build settings for MainActor-by-default isolation and strict concurrency
- `references/actor-isolation.md` — Actor isolation in MainActor-by-default projects
- `references/nonisolated-concurrent.md` — `nonisolated async` evolution, `@concurrent` attribute, Swift 6 concurrency patterns
- `references/ui.md` — SwiftUI patterns, @Observable, avoiding GeometryReader
- `references/swiftui-observation.md` — State-mutation rules for `@Observable`/`@State`: which contexts may write observed state, Observation dependency granularity, AppKit interop hazards (layout-pass crashes), two-way model ↔ AppKit sync direction rules, and the symptom → cause table for feedback loops
- `references/dark-mode.md` — Previewing light/dark mode, `colorScheme` environment vs `preferredColorScheme`, cross-platform adaptive backgrounds and colors
- `references/performance.md` — Performance optimization and resource efficiency
- `references/multiplatform.md` — iOS + macOS setup, SDK-specific build settings
- `references/implicit-return.md` — Modern implicit return patterns for single-expression functions, if expressions, and switch expressions
- `references/executables.md` — Executable entry points, `@main` annotation, file naming conventions, and command-line argument handling
- `references/transitive-dependencies.md` — Transitive module imports under SE-0409 (access-level on imports, Swift 6.0) and SE-0444 (member import visibility, Swift 6.1); migration guidance and `internal import` adoption
