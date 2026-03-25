# Swift Guidance Skill

A Claude Code skill that provides comprehensive guidance on Swift best practices, including modern concurrency patterns, logging, actor isolation, SwiftUI conventions, and performance optimization.

## Features

- **Swift Concurrency** — ensures code uses async/await instead of deprecated Combine or Dispatch patterns
- **Actor Isolation** — validates proper `@MainActor` and `nonisolated` annotations in MainActor-by-default projects
- **Structured Logging** — reviews Apple's unified logging system (`os.log`) usage with file-scoped loggers
- **SwiftUI Best Practices** — enforces `@Observable` macro and modern view composition patterns
- **Performance** — identifies optimization opportunities and efficient resource usage

## Installation

### From Local Directory

If you have this repository cloned locally:

```bash
cd SwiftGuidanceSkill
./install.sh
```

The script will create a symlink from `~/.claude/skills/swift-guidance` to your local directory, allowing live updates as you modify the skill files.

### From Git Repository

To install directly from GitHub:

```bash
REPO_URL=https://github.com/brennanMKE/SwiftGuidanceSkill.git ./install.sh
```

Or set the environment variable and run:

```bash
export REPO_URL=https://github.com/brennanMKE/SwiftGuidanceSkill.git
./install.sh
```

### Installation Prompt

The script will prompt if the skill already exists:

```
Replace with files from this repo? [Y/n]
```

- **Y** — removes the old installation and installs fresh
- **n** — cancels installation and keeps the existing version

## Usage

Once installed, the skill is available in Claude Code:

```
/swift-guidance
```

The skill will analyze Swift code for:

1. **Concurrency patterns** — flags Dispatch/Combine usage
2. **Actor isolation** — validates `nonisolated` and `@MainActor` annotations
3. **Logging** — checks for proper `os.log` setup with file-scoped loggers
4. **SwiftUI conventions** — enforces `@Observable` and modern patterns
5. **Performance** — identifies optimization opportunities

### Partial Reviews

You can request guidance on specific areas:

- `Check concurrency in this file` — loads `references/concurrency.md`
- `Review logging setup` — loads `references/logging.md`
- `Validate actor isolation` — loads `references/actor-isolation.md`
- `Check SwiftUI patterns` — loads `references/ui.md`
- `Analyze performance` — loads `references/performance.md`

## Removal

To remove the skill:

```bash
rm -rf ~/.claude/skills/swift-guidance
```

If you installed from a local directory (symlink), this only removes the link — your local repository remains untouched.

If you installed from a Git clone, this removes the cloned copy entirely.

## Reference Files

The skill uses the following reference materials:

- **`swift-guidance/references/concurrency.md`** — Modern Swift Concurrency patterns
- **`swift-guidance/references/actor-isolation.md`** — MainActor-by-default and proper isolation
- **`swift-guidance/references/logging.md`** — Apple's unified logging system setup and usage
- **`swift-guidance/references/ui.md`** — SwiftUI best practices
- **`swift-guidance/references/performance.md`** — Performance optimization guidelines

## Development

To modify the skill:

1. Install from the local directory (creates a symlink)
2. Edit files in `swift-guidance/`
3. Changes are immediately available in Claude Code (no reinstall needed)

## License

MIT
