# Swift Guidance Skill

A Claude Code skill that provides comprehensive guidance on Swift best practices, including modern concurrency patterns, logging, actor isolation, SwiftUI conventions, and performance optimization.

## Features

- **Swift Concurrency** — ensures code uses async/await instead of deprecated Combine or Dispatch patterns
- **Actor Isolation** — validates proper `@MainActor` and `nonisolated` annotations in MainActor-by-default projects
- **Structured Logging** — reviews Apple's unified logging system (`os.log`) usage with file-scoped loggers
- **SwiftUI Best Practices** — enforces `@Observable` macro and modern view composition patterns
- **Performance** — identifies optimization opportunities and efficient resource usage

## Installation

### Quick install (recommended) — `npx skills`

Installs across supported AI coding agents (Claude Code, Codex, Cursor, and others)
with one command:

```bash
npx skills add brennanMKE/SwiftGuidanceSkill --skill swift-guidance
```

Target specific tools, or run non-interactively:

```bash
npx skills add brennanMKE/SwiftGuidanceSkill --skill swift-guidance -a claude-code -a codex
npx skills add brennanMKE/SwiftGuidanceSkill --skill swift-guidance -a claude-code -g -y
```

> **Claude Code note:** if the skill installs but Claude Code doesn't see it, it
> likely landed in `~/.agents/skills/` without a `~/.claude/skills/` symlink. Fix:
> ```bash
> ln -s ~/.agents/skills/swift-guidance ~/.claude/skills/swift-guidance
> ```

### Manual install — `install.sh`

Clone the repo and run the installer. It links the skill into the global skills dir
of every detected tool (Claude Code, Codex):

```bash
git clone https://github.com/brennanMKE/SwiftGuidanceSkill.git
cd SwiftGuidanceSkill
./install.sh
```

Cursor has no global skills directory, so install it per project:

```bash
./install.sh --project /path/to/your/project   # links into <project>/.cursor/skills
```

Install straight from git without a manual clone (caches and updates on re-run):

```bash
REPO_URL=https://github.com/brennanMKE/SwiftGuidanceSkill.git ./install.sh
```

Because `install.sh` uses symlinks, edits to the skill files are picked up without
reinstalling.

### Where skills live

| Tool        | Global               | Project            |
|-------------|----------------------|--------------------|
| Claude Code | `~/.claude/skills/`  | `.claude/skills/`  |
| Codex CLI   | `~/.codex/skills/`   | `.codex/skills/`   |
| Cursor      | *(project only)*     | `.cursor/skills/`  |

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

```bash
rm ~/.claude/skills/swift-guidance
rm ~/.codex/skills/swift-guidance
rm /path/to/project/.cursor/skills/swift-guidance
```

Removing a symlink leaves the source repo untouched.

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
