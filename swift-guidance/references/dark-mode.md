# Light and Dark Mode in SwiftUI

SwiftUI views should render correctly in both light and dark appearance. Two areas catch people out: previewing each scheme (the preview APIs have subtle scoping rules), and writing colors, backgrounds, and assets that actually adapt at runtime. Get either wrong and you ship a UI that looks fine in development but broken in dark mode in production.

---

## The Core Pitfall: `.preferredColorScheme` Propagates to the Window

`.preferredColorScheme` is a *preference* — like `.navigationTitle`, it bubbles up the view tree and applies to the entire enclosing window/scene. If you stack two copies of a view in one preview and apply `.preferredColorScheme(.dark)` to the second, the whole preview canvas turns dark.

```swift
// ❌ AVOID: .preferredColorScheme on a child changes the entire preview window
#Preview {
    VStack {
        ContentView()                          // expected light — but renders dark
        ContentView()
            .preferredColorScheme(.dark)       // wins for the whole preview
    }
}
```

**Why this happens:** `preferredColorScheme` is a preference, not a scope-local override. It propagates up to the nearest enclosing presentation (window, sheet, popover) and flows down to every view in it. When views set conflicting values, a modifier **higher in the hierarchy overrides everything below it — even when its value is `nil`**. So `.preferredColorScheme(theme.scheme)` at the root with `theme == .system` makes the window follow the OS and silently ignores every child's `.light`/`.dark`. Only when no ancestor sets the modifier do siblings compete, and then the **first non-nil preference in view order wins** (Apple docs). Verified on macOS 27 (Dark Mode host): sibling A `.light` + sibling B `.dark` → light window, reversed → dark; outer `.light` beat inner `.dark`; outer `nil` + inner `.light`/`.dark` → window followed the OS (dark), children ignored.

---

## Solution: Use `\.colorScheme` Environment for Side-by-Side Previews

To render light and dark in the *same* preview window, override the `colorScheme` environment value. Environment values are scoped to their subtree, so each branch gets its own appearance.

```swift
// ✅ PREFERRED: environment override is subtree-scoped
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        ContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .environment(\.colorScheme, .light)

        ContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}
```

**Why this works:**
- `\.colorScheme` is an environment value, applied only to its subtree.
- Each half resolves semantic colors (`.background`, `.primary`, `Color(.label)`, etc.) against its own scheme.
- A background is required — a transparent view shows the canvas color, defeating the visual.

---

## Solution: Separate Named Previews

When you don't need a single side-by-side comparison, prefer multiple `#Preview` blocks. Each gets its own canvas in Xcode and `.preferredColorScheme` works correctly because each is its own window.

```swift
// ✅ PREFERRED: one preview per appearance, named for clarity
#Preview("Light") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
```

**Why this is often best:**
- Xcode shows previews as a tabbed list — easy to flip between.
- No layout gymnastics, no manual backgrounds.
- `.preferredColorScheme` works as intended at the preview root.

---

## Backgrounds: Use Semantic Styles, Not UIKit-Only Colors

A common mistake is reaching for `Color(.systemBackground)`. That's a `UIColor` color — it compiles on iOS and visionOS but **not on macOS** (`reference to member 'systemBackground' cannot be resolved`) or **tvOS** (`'systemBackground' is unavailable in tvOS`), so it breaks multiplatform targets and cross-platform packages.

```swift
// ❌ AVOID: UIKit-only, breaks macOS builds
.background(Color(.systemBackground))

// ❌ AVOID: hardcoded — does not adapt to color scheme
.background(Color.white)
```

```swift
// ✅ PREFERRED: SwiftUI BackgroundStyle, cross-platform, scheme-aware
.background(.background)
```

`.background(.background)` uses SwiftUI's `BackgroundStyle` shape style, which resolves to the system window/content background on iOS, macOS, tvOS, and visionOS, and respects `colorScheme` automatically.

**If you need the platform-specific UIKit/AppKit color:**

```swift
// ✅ ACCEPTABLE: explicit platform branch when you really need the OS color
#if os(macOS)
.background(Color(nsColor: .windowBackgroundColor))
#else
.background(Color(uiColor: .systemBackground))
#endif
```

See `multiplatform.md` for the broader strategy on `#if os(...)` branching and SDK-specific build settings, which avoids scattering platform checks across your view code.

---

## Custom Colors Must Adapt

Hardcoded `Color.white` / `Color.black` / `Color.gray` ignore the color scheme. Define adaptive colors instead.

**Option 1: Asset catalog with Any/Dark variants (recommended for designed palettes)**

Add a Color Set in `Assets.xcassets`, fill in the Any Appearance and Dark Appearance values, then reference it. In Xcode 15+ with asset symbol generation enabled (the default), prefer the generated symbol over the stringly-typed initializer — typos become compile errors instead of silently rendering as bright pink at runtime.

```swift
// ✅ PREFERRED: generated asset symbol (Xcode 15+), type-checked
Text("Title")
    .foregroundStyle(Color.brandSurface)

// ✅ ACCEPTABLE: stringly-typed initializer (older Xcode, or dynamic names)
Text("Title")
    .foregroundStyle(Color("BrandSurface"))
```

**Option 2: Trait-based closure when an asset catalog isn't available**

`Color(light:dark:)` is **not** a built-in SwiftUI initializer — if you've seen it in a codebase, it's a custom extension wrapping the trait-based UIKit/AppKit APIs below. Prefer the asset catalog; reach for these closures only when an inline, code-defined color is genuinely needed (e.g., in a Swift package without resource bundles).

```swift
// ✅ iOS / iPadOS / tvOS / visionOS — adaptive Color via UIColor trait closure
extension Color {
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.12, alpha: 1)
            : .white
    })
}
```

```swift
// ✅ macOS — adaptive Color via NSColor appearance closure
extension Color {
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1)
            : .white
    })
}
```

These closures re-evaluate whenever the trait collection or appearance changes, so the color stays correct across runtime scheme switches. A common project-level helper wraps both behind a single `Color(light:dark:)` initializer — handy, but not standard.

**Option 3: Read `\.colorScheme` directly (only when behavior, not just color, must change)**

```swift
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            // Drop shadows are nearly invisible on dark surfaces; swap for a subtle hairline border instead.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.15), radius: 6, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 1)
            )
    }
}
```

Use this sparingly — prefer adaptive colors and asset-catalog variants. Branching on `colorScheme` is appropriate when the *treatment* differs between schemes (shadow vs. border, blur radius, animation timing), not just the color value.

---

## Images and SF Symbols

### Foreground styles adapt automatically

`.foregroundStyle(.primary)`, `.foregroundStyle(.secondary)`, `.tint`, and SF Symbols all adapt to color scheme by default. You almost never need to override them per-scheme.

```swift
// ✅ Adapts automatically — no branching needed
Image(systemName: "globe")
    .foregroundStyle(.tint)
Text("Hello")        // .primary text color, adapts automatically
```

### SF Symbol rendering modes

For multi-color or layered symbols, prefer the rendering modes that resolve against the current scheme over hardcoded fills.

```swift
// ✅ Adapts: hierarchical/palette/multicolor honor the color scheme and tint
Image(systemName: "battery.75percent")
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(.tint)

// ❌ AVOID: a fixed black fill disappears against a dark surface
Image(systemName: "battery.75percent")
    .foregroundStyle(.black)
```

### Image assets need dark variants too

Raster and vector assets in `Assets.xcassets` support an "Appearances → Any, Dark" split the same way Color Sets do. A single asset name resolves to the right artwork at runtime — no `colorScheme` branching required.

```swift
// ✅ Asset-catalog Image with Any/Dark variants — generated symbol, adapts automatically
Image(.logo)

// ❌ AVOID: branching on colorScheme to swap image names — the asset catalog should do this
Image(colorScheme == .dark ? "logo-dark" : "logo-light")
```

If you find yourself swapping image names by scheme, that's a signal the variants belong inside one asset, not as two separate ones.

---

## Don't Forget Materials

`.regularMaterial`, `.thinMaterial`, etc. are scheme-aware blurs. Prefer them over hand-rolled translucent overlays that won't adapt.

```swift
// ✅ Material adapts to light/dark automatically
.background(.regularMaterial)
```

---

## Common Pitfalls

| Pitfall | Problem | Solution |
|---------|---------|----------|
| `.preferredColorScheme` on a child view in a stacked preview | Propagates to the whole window; both halves render the same scheme | Use `.environment(\.colorScheme, …)` per branch, or split into two `#Preview` blocks |
| `Color(.systemBackground)` | UIKit color; breaks macOS and tvOS builds | Use `.background(.background)` |
| Hardcoded `Color.white` / `Color.black` | Ignores scheme; light text on light background or vice versa | Use an asset-catalog Color Set, a trait-based `UIColor`/`NSColor` closure, or `.primary` / `.secondary` |
| `Image("logo-dark")` swapped by `\.colorScheme` | Two assets where one would do; easy to forget one variant | Add Any/Dark appearances inside a single asset and use `Image(.logo)` |
| No background on previewed view | Picks up canvas color, masking the bug you're trying to verify | Add `.background(.background)` and `.frame(maxWidth: .infinity, maxHeight: .infinity)` |
| Branching on `colorScheme` for color values | Manual work; doesn't extend to high-contrast accessibility settings | Define adaptive colors in the asset catalog |
| Hardcoded shadow colors | Black shadows on dark backgrounds disappear | Use `.shadow(color: .primary.opacity(0.2), …)` or a scheme-aware asset color |

---

## Severity Guide

When reviewing dark-mode issues, classify them so the skill's stopping rule (see `SKILL.md`) applies consistently:

- **CRITICAL** — illegible UI in one scheme: hardcoded text or background colors that produce invisible content (white text on white background, black icon on black surface). User-facing breakage; ship-blocker.
- **HIGH** — `Color(.systemBackground)` or other UIKit-only color initializers in cross-platform code (breaks macOS / tvOS builds); `.preferredColorScheme` applied to a child view inside a stacked preview (silently misleads the developer); hardcoded `Color.white` / `Color.black` / `Color.gray` in user-facing UI.
- **MEDIUM** — no dark-mode preview at all for a non-trivial view; branching on `\.colorScheme` purely to pick a color where an adaptive color would suffice; hardcoded shadow colors that vanish on dark surfaces.
- **NICE-TO-HAVE** — stringly-typed `Color("Name")` instead of generated asset symbols; minor naming preferences for color sets.

---

## Code Review Checklist

When reviewing SwiftUI views for dark mode support:

- [ ] Stacked previews use `.environment(\.colorScheme, …)`, not `.preferredColorScheme`, to avoid window-level propagation
- [ ] Each preview branch has an explicit background (`.background(.background)`) so the scheme is visually verifiable
- [ ] No use of `Color(.systemBackground)` or other UIKit-only color initializers in cross-platform code
- [ ] Custom colors come from the asset catalog (preferring generated `Color.brandSurface` symbols over `Color("Name")`) or a trait-based `UIColor`/`NSColor` closure — never hardcoded `.white` / `.black` / `.gray`
- [ ] Shadows, borders, and overlays use semantic or adaptive colors
- [ ] Image assets with light/dark variants live inside one asset, not two `Image("foo-light")` / `Image("foo-dark")` swapped via `\.colorScheme`
- [ ] SF Symbols use rendering modes (`.hierarchical`, `.palette`, `.multicolor`) rather than hardcoded fills
- [ ] At least one preview exists for both light and dark appearance (named previews or split-view)
- [ ] No unnecessary branching on `\.colorScheme` where an adaptive color would suffice
