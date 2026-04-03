# Swift Implicit Return Reference

This document is intended as a compact reference for a Claude Code skill.

## Scope

Swift supports implicit return when the entire body of a function, getter, closure, or subscript getter is a single expression.

For this reference, focus on these three cases:

1. Single-expression functions
2. `if` expressions used as the function's single expression
3. `switch` expressions used as the function's single expression

## Rule of Thumb

Use implicit return only when the whole body produces one value.

That means these are valid:

```swift
func doubled(_ value: Int) -> Int {
    value * 2
}
```

```swift
func statusText(isEnabled: Bool) -> String {
    if isEnabled {
        "enabled"
    } else {
        "disabled"
    }
}
```

```swift
enum Direction {
    case north
    case south
    case east
    case west
}

func symbol(for direction: Direction) -> String {
    switch direction {
    case .north:
        "↑"
    case .south:
        "↓"
    case .east:
        "→"
    case .west:
        "←"
    }
}
```

## Functions

A function can omit `return` when its body is a single expression.

```swift
func square(_ value: Int) -> Int {
    value * value
}
```

Equivalent explicit form:

```swift
func square(_ value: Int) -> Int {
    return value * value
}
```

### Good uses

```swift
func greeting(for name: String) -> String {
    "Hello, \(name)"
}
```

```swift
func isEven(_ value: Int) -> Bool {
    value.isMultiple(of: 2)
}
```

### Not valid

This is **not** implicit return, because the body contains more than one statement:

```swift
func squarePlusOne(_ value: Int) -> Int {
    let squared = value * value
    return squared + 1
}
```

When there is setup work, keep `return` explicit.

## `if` Expressions

Swift allows `if` to be used as an expression in contexts like assignment and returning a value.

When an `if` expression is the only expression in a function body, the function can also use implicit return.

```swift
func priorityLabel(for score: Int) -> String {
    if score >= 90 {
        "high"
    } else if score >= 60 {
        "medium"
    } else {
        "low"
    }
}
```

### Important rules

Each branch must produce a value.

```swift
func accessText(isAdmin: Bool) -> String {
    if isAdmin {
        "full"
    } else {
        "limited"
    }
}
```

All branches must resolve to the same type.

```swift
func badgeCountText(count: Int) -> String {
    if count == 0 {
        "none"
    } else {
        "\(count)"
    }
}
```

### Style guidance

Prefer this form when the whole purpose of the `if` is to choose a value.

Prefer the older statement form when branches perform work instead of simply producing a value.

Good:

```swift
func backgroundOpacity(isSelected: Bool) -> Double {
    if isSelected {
        1.0
    } else {
        0.35
    }
}
```

Less suitable:

```swift
func loadMessage(isCached: Bool) -> String {
    if isCached {
        print("Using cache")
        return "cached"
    } else {
        print("Loading fresh data")
        return "fresh"
    }
}
```

In the second example, use explicit `return` and treat the `if` as a statement.

## `switch` Expressions

Swift also allows `switch` to be used as an expression when each case produces a value.

When that `switch` expression is the whole function body, the function can use implicit return.

```swift
enum HTTPStatusKind {
    case informational
    case success
    case redirect
    case clientError
    case serverError
}

func categoryName(for kind: HTTPStatusKind) -> String {
    switch kind {
    case .informational:
        "1xx"
    case .success:
        "2xx"
    case .redirect:
        "3xx"
    case .clientError:
        "4xx"
    case .serverError:
        "5xx"
    }
}
```

### Important rules

Each case must produce a value.

```swift
func shortName(for direction: Direction) -> String {
    switch direction {
    case .north:
        "N"
    case .south:
        "S"
    case .east:
        "E"
    case .west:
        "W"
    }
}
```

All cases must resolve to the same type.

```swift
func axis(for direction: Direction) -> String {
    switch direction {
    case .north, .south:
        "vertical"
    case .east, .west:
        "horizontal"
    }
}
```

### Style guidance

Prefer a `switch` expression when mapping one value to another value.

That is often the clearest form for enums.

## Recommended Skill Rules

Use these rules in a Claude Code skill:

```markdown
- Prefer implicit return for single-expression functions.
- Prefer implicit return when the entire function body is a single `if` expression.
- Prefer implicit return when the entire function body is a single `switch` expression.
- Keep `return` explicit when the function body contains setup statements, logging, mutation, or multiple steps.
- For `if` and `switch` expressions, make every branch produce the same output type.
- Do not rewrite multi-statement branches into expression style unless the result is clearly better.
```

## Practical Rewrite Patterns

### Function expression

Before:

```swift
func title(for count: Int) -> String {
    return "Count: \(count)"
}
```

After:

```swift
func title(for count: Int) -> String {
    "Count: \(count)"
}
```

### `if` expression

Before:

```swift
func roleLabel(isAdmin: Bool) -> String {
    if isAdmin {
        return "Admin"
    } else {
        return "User"
    }
}
```

After:

```swift
func roleLabel(isAdmin: Bool) -> String {
    if isAdmin {
        "Admin"
    } else {
        "User"
    }
}
```

### `switch` expression

Before:

```swift
func symbol(for direction: Direction) -> String {
    switch direction {
    case .north:
        return "↑"
    case .south:
        return "↓"
    case .east:
        return "→"
    case .west:
        return "←"
    }
}
```

After:

```swift
func symbol(for direction: Direction) -> String {
    switch direction {
    case .north:
        "↑"
    case .south:
        "↓"
    case .east:
        "→"
    case .west:
        "←"
    }
}
```

## When Not to Use It

Avoid implicit return when:

- The function has intermediate local variables that improve readability
- The branches do side effects such as logging, mutation, or metrics
- The logic is long enough that explicit `return` improves scanning
- You are forcing expression style onto code that is naturally statement-based

Example:

```swift
func processedName(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let collapsed = trimmed.replacingOccurrences(of: "  ", with: " ")
    return collapsed.uppercased()
}
```

This is better left with explicit `return`.

## Bottom Line

For modern Swift code:

- Use implicit return for simple single-expression functions.
- Use it naturally with `if` expressions.
- Use it naturally with `switch` expressions.
- Do not force expression style onto multi-step logic.
- Prefer readability over terseness.

## Sources

- The Swift Programming Language: Functions
- The Swift Programming Language: Expressions
- The Swift Programming Language: Control Flow
- Swift 5.9 release notes and revision history for the Swift book
