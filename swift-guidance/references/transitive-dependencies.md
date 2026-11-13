# Transitive Module Imports (SE-0409 & SE-0444)

Two Swift Evolution proposals tighten how transitively-imported modules behave at
compile time. **SE-0409** (Swift 6.0) adds access-level modifiers on `import`.
**SE-0444** (Swift 6.1) stops extension members from indirect dependencies
leaking into scope. SE-0409 keeps implementation-detail dependencies out of a
module's public API (and, for library-evolution modules, out of clients' builds);
SE-0444 prevents name-lookup ambiguity and undeclared-dependency leaks. Both can
break code that relied on transitive availability.

Claims and diagnostics below were verified with Swift 6.4.2 / Xcode 27.2
(multi-module SwiftPM packages, `-Rmodule-loading`, `-print-supported-features`).

**Status in Swift 6.4:** both strict behaviors are still **upcoming features** —
no shipping language mode enables them (the compiler lists them for a future
Swift 7 mode). **But Xcode 27's new-project template sets
`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`**, so SE-0444 is on in
new Xcode projects. Check the build settings or `swiftSettings` before assuming
either way.

---

## Core Principles

1. **Mark imports `public` only when the dependency's types appear in your module's public API** — parameters, return types, public stored properties, public conformances.
2. **Use `internal import` for implementation-detail dependencies** — it keeps them out of your public API and, for library-evolution modules, out of clients' builds.
3. **Import every module whose members you use** — including modules that define extension methods or properties on types you got from elsewhere.
4. **Don't use `@_implementationOnly`** — it's unsafe in non-resilient modules and deprecated in practice; `internal import` replaces it.
5. **Treat SE-0409 / SE-0444 errors as graph signals** — the declared dependency graph is wrong.

---

## SE-0409: Access-Level Modifiers on Import Declarations

**Shipped in:** Swift 6.0 (syntax works in every language mode, including `-swift-version 5`)

### What changed

```swift
public import Foo       // Foo is part of this module's public API
package import Bar      // Bar is visible package-wide
internal import Baz     // Baz is an implementation detail
private import Qux      // Qux is visible only within this file
```

**Effect on clients depends on library evolution:**
- **Library-evolution (resilient) modules** (`BUILD_LIBRARY_FOR_DISTRIBUTION` /
  `-enable-library-evolution`): clients skip loading `internal`-or-lower
  dependencies (verified with `-Rmodule-loading`).
- **Ordinary modules** (most SwiftPM targets and app frameworks): clients still
  load every dependency — SE-0409: "All dependencies of a non-resilient module
  must be loaded by transitive clients." `internal import` then only tightens
  type-checking of your public API.

### The breaking change

An `import` without a modifier is implicitly `public` in Swift 5 and 6 modes.
The `InternalImportsByDefault` upcoming feature flips the default to `internal`.
With the flag on — or whenever you write `internal import` explicitly — using a
non-publicly-imported module's types in public API is an error.

### Error patterns

```
// Public signature using the type:
error: function cannot be declared public because its result uses an internal type
note: struct 'Widget' is imported by this file as 'internal' from 'WidgetCore'

// Public conformance / extension:
error: cannot use protocol 'Describable' in a public or '@usableFromInline' conformance; 'WidgetCore' was not imported publicly
error: cannot use struct 'Widget' in an extension with public or '@usableFromInline' members; 'WidgetCore' was not imported publicly
```

### Fix

Promote only the import whose types are in your public API:

```swift
// ❌ Fails under InternalImportsByDefault
import FooModule

public func makeFoo() -> Foo { ... }

// ✅ Explicit access level on the import that's part of the API
public import FooModule

public func makeFoo() -> Foo { ... }
```

---

## SE-0444: Member Import Visibility

**Shipped in:** Swift 6.1 (`MemberImportVisibility` upcoming feature)

### What changed

Top-level declarations from a transitively-imported module were already out of
scope without a direct import, but **members found through member lookup**
leaked through. With SE-0444, those members require a direct import of the
module that declares them.

**Covered:** extension methods, properties, subscripts, initializers, and nested
types — including members of constrained extensions
(`extension Array where Element == Foo`).

**Not covered (yet):** protocol conformances and operator lookup — SE-0444 lists
both as future directions (verified: using a conformance declared in an
unimported module still compiles with the flag on). Macros and other top-level
names always required a direct import.

An accepted amendment lets a default implementation in an *unconstrained*
protocol extension, in the protocol's own module, satisfy a requirement without
being imported.

### Error pattern

```
error: instance method 'render()' is not available due to missing import of defining module 'WidgetRender' [#MemberImportVisibility]
```

### Fix

Add the direct import in the file that uses the member:

```swift
// ❌ Relies on ModuleA's transitive import of WidgetRender
import ModuleA

let w = Widget()
w.render()              // render() is declared in WidgetRender's extension on Widget

// ✅ Import the module that declares the member
import ModuleA
import WidgetRender

let w = Widget()
w.render()
```

---

## Default Status by Swift Version

| Swift version | Access-level import syntax | `InternalImportsByDefault` | `MemberImportVisibility` |
|---|---|---|---|
| 5.9 – 5.10 | experimental flag (`AccessLevelOnImport`) | — | not available |
| 6.0 | always available | upcoming, opt-in | not available |
| 6.1 – 6.4 | always available | upcoming, opt-in | upcoming, opt-in (**on in Xcode 27 new-project templates**) |
| future (Swift 7 mode) | always available | default | default |

---

## Enabling and Migrating

### Swift packages

```swift
.target(
    name: "MyLibrary",
    swiftSettings: [
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),  // mainly for libraries with public API
    ]
)
```

`swift package migrate --to-feature MemberImportVisibility` adds the missing imports.

### Xcode targets

Use the dedicated build settings (not `OTHER_SWIFT_FLAGS`):

- **Member Import Visibility** — `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` = `YES` / `MIGRATE` / `NO`. `MIGRATE` emits fix-it warnings (`import of module 'X' is required`) instead of errors.
- **Default Internal Imports** — `SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT` = `YES` / `NO`.

### Suggested order

1. **`MemberImportVisibility` first** — already on in new Xcode projects; use `MIGRATE` or `swift package migrate`, then add direct imports (and direct `Package.swift` dependencies) where needed.
2. **`InternalImportsByDefault`** for library modules with public API — fix errors by promoting only the imports whose types are public. App targets usually see few or no errors from it.
3. **Use `internal import` deliberately** for implementation-detail dependencies.

---

## Common Pitfalls

| Pitfall | Problem | Solution |
|---|---|---|
| Marking every `import` `public` to silence SE-0409 errors | Widens the public API's dependency surface; for resilient modules, clients reload every dependency | `public` only for imports whose types appear in public API |
| New `@_implementationOnly import` | Predates SE-0409; unsafe in non-resilient modules (can cause runtime crashes, incl. with `@testable`); Swift 6.4 warns `[#ImplementationOnlyDeprecated]` | Use `internal import`. Neither changes runtime loading — both are compile-time |
| Test file uses an extension member that "works" in the app target | `@testable import MyApp` doesn't make `MyApp`'s dependencies' members visible under SE-0444 | Add the direct `import` in the test file |
| Re-exporting a transitive type via `typealias` to dodge SE-0444 | Hides the dependency relationship | Import the defining module where the member is used |
| Treating SE-0444 errors as a compiler bug | They reflect a real undeclared edge in the graph | Add the direct import; declare the dependency in `Package.swift` |
| `public import` for a module used only in `internal` API | Unnecessarily exposes the dependency | Downgrade to `internal import` |

---

## Severity Guide

- **CRITICAL** — none specific to this domain; these errors block the build and the compiler reports them.
- **HIGH** — new `@_implementationOnly` in Swift 6+ code (use `internal import`); blanket `public import` added only to silence SE-0409 errors; `typealias` re-exports used to dodge SE-0444.
- **MEDIUM** — library modules that could mark imports `internal` but don't; test targets relying on transitive members.
- **NICE-TO-HAVE** — import ordering.

---

## Code Review Checklist

- [ ] Public API mentioning a dependency's types uses `public import` for that module
- [ ] Implementation-detail imports use `internal import`, not `@_implementationOnly`
- [ ] Files that use extension members import the declaring module directly
- [ ] `Package.swift` declares modules required to satisfy SE-0444 as direct dependencies
- [ ] "not imported publicly" / "missing import of defining module" errors are fixed at the import site
- [ ] No blanket `public import`s whose types aren't in the public API
- [ ] Build settings checked: Member Import Visibility is on in new Xcode projects

---

## Sources

- [SE-0409: Access-level modifiers on import declarations](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md)
- [SE-0444: Member import visibility](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md)
