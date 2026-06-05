# Transitive Module Imports (SE-0409 & SE-0444)

Two Swift Evolution proposals tighten how transitively-imported modules behave at compile time. **SE-0409** (Swift 6.0) introduces access-level modifiers on `import`. **SE-0444** (Swift 6.1) closes a long-standing leak where extension members from indirect dependencies were silently in scope. Both speed up builds in large dependency graphs, and both can break code that previously compiled by relying on transitive availability.

**Both behaviours are gated behind upcoming-feature flags and are still opt-in as of Swift 6.2** — see [Default Status by Swift Version](#default-status-by-swift-version) below before assuming the new rules are active in your project.

---

## Core Principles

1. **Mark imports `public` only when the dependency's types appear in your module's public API** — parameters, return types, public stored properties, public conformances.
2. **Use `internal import` for implementation-detail dependencies** — clients of your module skip loading them, which is the whole point of the build-speed win.
3. **Import every module whose declarations you actually reference** — including modules that define extension methods, operators, or conformances on types you got from somewhere else.
4. **Don't reach for `@_implementationOnly`** — it's an underscore-prefixed, unstable spelling. `internal import` is the supported replacement.
5. **Treat SE-0409 / SE-0444 errors as graph signals, not compiler noise** — the compiler is telling you the declared dependency graph is wrong.

---

## SE-0409: Access-Level Modifiers on Import Declarations

**Shipped in:** Swift 6.0

### What changed

Imports now accept any access-level modifier. The compiler uses that to decide whether transitive clients of your module need to load the dependency at all.

```swift
public import Foo       // Foo is part of this module's public API
package import Bar      // Bar is visible package-wide
internal import Baz     // Baz is an implementation detail
private import Qux      // Qux is visible only within this file
```

When a dependency is imported at `internal` or lower, downstream clients of your module are built without loading it — fewer `.swiftmodule` files to read, faster incremental builds, smaller distributions.

### The breaking change

In Swift 5 and Swift 6 (including 6.2 as shipped), an `import` without an access modifier is implicitly `public`. The `InternalImportsByDefault` upcoming feature flips that implicit default to `internal`. With the flag enabled — *or* whenever you write `internal import` (or lower) explicitly — the build fails if a non-public-imported module's type appears in your module's public API.

The proposal targets "a future language mode" for making the new default automatic; it has not been promoted yet.

### Error pattern

```
cannot use type 'Foo' here; 'FooModule' was not imported publicly
```

### Fix

Promote the relevant import — but only that one. Don't add `public` to every import to make errors stop; you'll undo the build-speed benefit.

```swift
// ❌ AVOID: implicit public worked in Swift 5, fails under InternalImportsByDefault
import FooModule

public func makeFoo() -> Foo { ... }   // Foo's module wasn't imported publicly

// ✅ PREFERRED: explicit access level on the import that's actually part of the API
public import FooModule

public func makeFoo() -> Foo { ... }
```

### Feature flags

| Flag | Effect |
|---|---|
| `AccessLevelOnImport` | Enables the access-level syntax (on by default in Swift 6) |
| `InternalImportsByDefault` | Switches the implicit access level from `public` to `internal` (upcoming feature; recommended for Swift 6+ adoption) |

---

## SE-0444: Member Import Visibility

**Shipped in:** Swift 6.1

### What changed

Before SE-0444, top-level declarations from a transitively-imported module were correctly out of scope without a direct import — but **member declarations** leaked through. SE-0444 makes member visibility consistent with top-level visibility: every declaration you reference must come from a module you import directly.

"Member declarations" here is broader than just extension methods. The same rule applies to:

- extension methods and computed properties
- custom operators declared in another module
- protocol conformances on a type, when the conformance is declared elsewhere
- generic constraints introduced by extensions (e.g. `extension Array where Element: Foo`)
- macros declared in another module

If the symbol you reference is *defined* in module `M`, you need a direct `import M` in the file that uses it — even if your direct dependency happens to import `M` for its own reasons.

### Error pattern

```
referencing instance method 'render()' requires import of module 'WidgetKit'
```

### Fix

Add the direct import at the file that uses the member. Don't try to re-export the member through your direct dependency.

```swift
// ❌ AVOID: relying on ModuleA's transitive import of WidgetKit
import ModuleA

let w = Widget()
w.render()              // render() is defined in WidgetKit's extension on Widget

// ✅ PREFERRED: import the module that actually defines the member
import ModuleA
import WidgetKit

let w = Widget()
w.render()
```

The same rule applies to conformances. If you use a type from one module and a conformance defined in a third module, you must import the third module wherever the conformance is needed.

### Feature flag

| Flag | Effect |
|---|---|
| `MemberImportVisibility` | Enforces direct-import rules for member declarations (introduced in Swift 6.1; still opt-in as of Swift 6.2) |

---

## Default Status by Swift Version

Both proposals ship as **upcoming features** — opt-in flags that preview a future default. Knowing the status matters because it determines whether you need to add anything to `Package.swift` (or `OTHER_SWIFT_FLAGS`) to see the new errors.

| Swift version | `AccessLevelOnImport` syntax | `InternalImportsByDefault` (SE-0409 default change) | `MemberImportVisibility` (SE-0444) |
|---|---|---|---|
| 5.9 – 5.10 | available as upcoming feature | upcoming feature, opt-in | not available |
| 6.0 | always on | upcoming feature, opt-in | not available |
| 6.1 | always on | upcoming feature, opt-in | upcoming feature, opt-in |
| **6.2** | **always on** | **upcoming feature, opt-in** | **upcoming feature, opt-in** |
| future language mode | always on | becomes default | expected to become default |

**Practical takeaway for Swift 6.2 projects:** the access-level syntax (`public import`, `internal import`, etc.) works without any flag, but the *strict* behaviours don't. If you want the SE-0409 default-to-`internal` enforcement or the SE-0444 direct-import enforcement to kick in, you must enable the upcoming features explicitly. Without them, code that compiled before 6.2 will keep compiling.

---

## Migration Order

Because both behaviours are still opt-in, "migration" in current Swift means deliberately turning them on so the compiler surfaces the work.

### Enabling the upcoming features

In a Swift Package, add the flags to each target's `swiftSettings`:

```swift
.target(
    name: "MyLibrary",
    dependencies: [...],
    swiftSettings: [
        .enableUpcomingFeature("InternalImportsByDefault"),  // SE-0409 strict default
        .enableUpcomingFeature("MemberImportVisibility"),    // SE-0444 strict member resolution
    ]
)
```

In Xcode targets that aren't packages, set `OTHER_SWIFT_FLAGS` to include `-enable-upcoming-feature InternalImportsByDefault -enable-upcoming-feature MemberImportVisibility` (or use the equivalent build-setting UI).

### Suggested order

1. **Enable `InternalImportsByDefault` first** and address SE-0409 errors. Most are one-line fixes (`import` → `public import`) on imports whose types appear in your module's public API.
2. **Then enable `MemberImportVisibility`** and address SE-0444 errors by adding direct imports at the use site.
3. **Use `internal import` deliberately** for implementation-detail dependencies. Every dependency you keep non-public stops propagating to downstream clients, shaving load time off their builds.
4. **Promote silent transitive deps to direct deps in `Package.swift`** when SE-0444 forces you to import them. The compiler is telling you a dependency you've been using implicitly should be declared explicitly.

Doing the steps in this order prevents a wall of mixed errors — SE-0409 errors usually outnumber SE-0444 errors and benefit from being cleared first.

---

## Common Pitfalls

| Pitfall | Problem | Solution |
|---|---|---|
| Marking every `import` as `public` to silence SE-0409 errors | Defeats the build-speed benefit; transitive clients reload every dependency | Mark `public` only for imports whose types appear in your public API |
| Reaching for `@_implementationOnly import` for new code | Underscore-prefixed, unstable spelling that predates SE-0409 | Use `internal import` (or rely on the `InternalImportsByDefault` default once enabled). Note: the two are not perfectly equivalent — `@_implementationOnly` *also* prevents the dependency from being loaded at runtime by clients, while `internal import` only hides it at the source/API level. For most projects this difference doesn't matter, but binary-size or load-time-sensitive code may need to keep `@_implementationOnly` for now. |
| Test target uses an extension method that "works fine" in the app target | `@testable import MyApp` does not transitively pull in `MyApp`'s dependencies under SE-0444; the test file needs its own direct import | Add the direct `import` in the test file alongside the `@testable import` |
| Re-exporting a transitive type via `typealias` to avoid an SE-0444 error | Hides the dependency relationship; surprises future readers and consumers | Add the direct import where the member is referenced |
| Treating SE-0444 errors as a compiler bug | They reflect a real undeclared edge in your dependency graph | Add the direct import; if needed, declare the package as a direct dependency in `Package.swift` |
| Adding `public import` for a module whose types are only in `internal` API | Forces every client to load a module they never see | Downgrade to `internal import` |

---

## Severity Guide

When reviewing transitive-import issues, classify them so the skill's stopping rule (see `SKILL.md`) applies consistently:

- **CRITICAL** — none specific to this domain; SE-0409 / SE-0444 errors block the build, which the compiler already reports loudly.
- **HIGH** — `@_implementationOnly` newly added in code targeting Swift 6+ (use `internal import` instead unless the runtime-hiding semantics are deliberately needed); blanket `public import` annotations applied just to silence SE-0409 errors (defeats the build-speed benefit and obscures the public surface); workarounds that re-export a transitive type via `typealias` to avoid an SE-0444 error.
- **MEDIUM** — modules that could mark several imports `internal` but don't, leaving the build-graph wider than it needs to be; test targets that rely on transitive members instead of importing directly.
- **NICE-TO-HAVE** — cosmetic ordering of imports, or migrating from `@_implementationOnly` to `internal import` when both still work fine.

---

## Code Review Checklist

When reviewing Swift modules for transitive-import correctness:

- [ ] Public API surface that mentions a dependency's types uses `public import` for that module
- [ ] Implementation-detail imports use `internal import` (or rely on the `InternalImportsByDefault` default) rather than `@_implementationOnly`
- [ ] Files that use extension methods, operators, or protocol conformances import the defining module directly
- [ ] `Package.swift` declares as direct dependencies any modules required to satisfy SE-0444 errors
- [ ] "Was not imported publicly" or "requires import of module" errors are fixed at the import site, not papered over
- [ ] No blanket `public import` annotations whose types aren't actually in the module's public API
- [ ] No new `@_implementationOnly import` statements in code targeting Swift 6+

---

## Sources

- [SE-0409: Access-level modifiers on import declarations](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md)
- [SE-0444: Member import visibility](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md)
