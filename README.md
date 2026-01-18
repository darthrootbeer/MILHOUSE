# Milhouse

A simplified autonomous development loop inspired by Ralph Wiggum, with deliberate context management and heuristic-based rotation.

## Overview

Milhouse is a streamlined version of the Ralph autonomous iteration technique for Cursor. It enables autonomous AI development with context rotation, but uses simpler heuristics instead of precise token tracking.

## Project Structure

```
milhouse/
├── .cursor/
│   ├── commands → TOOLBOX/.cursor/commands
│   └── rules → TOOLBOX/.cursor/rules
├── docs/              # Documentation and references
├── scripts/           # Bash scripts for Milhouse
├── README.md          # This file
├── TODO.md            # Task tracking
├── project-log.md     # Decision tracking and version history
├── MILHOUSE_PLAN.md   # Detailed implementation plan
├── UI_RULES.md        # Milhouse-specific UI design rules
└── GUM_TUI_RULES.md   # General gum TUI design principles
```

## Key Concepts

- **Heuristic-based rotation**: Rotate context based on time, file count, or iteration number
- **Single script architecture**: One main script instead of multiple modules
- **Git as audit trail**: Use git log/diff for analysis instead of separate logs
- **Simpler state management**: Minimal state files, rely on git for history

## Getting Started

1. Review `MILHOUSE_PLAN.md` for the full implementation plan
2. Check `UI_RULES.md` for Milhouse-specific UI guidelines
3. Reference `GUM_TUI_RULES.md` for general TUI best practices

## Key Files

- `README.md` - This file
- `TODO.md` - Task tracking
- `project-log.md` - Decision tracking and version history
- `MILHOUSE_PLAN.md` - Detailed implementation plan and analysis
- `UI_RULES.md` - UI design rules for Milhouse
- `GUM_TUI_RULES.md` - General gum/TUI design principles

## Status

🚧 **In Planning** - Project structure and design principles established. Implementation pending.
