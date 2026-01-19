# Milhouse

A simplified autonomous development loop inspired by Ralph Wiggum, with deliberate context management and heuristic-based rotation.

## Overview

Milhouse is a streamlined version of the Ralph autonomous iteration technique for Cursor. It enables autonomous AI development with context rotation, but uses simpler heuristics instead of precise token tracking.

## Project Structure

```text
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

### Install into another project

From the project you want to use Milhouse in:

```bash
bash "/path/to/milhouse/install.sh" --yes --force --target "$(pwd)"
```

Then run:

```bash
./scripts/milhouse.sh
```

### Follow along (logs)

- `tail -f .milhouse/out.txt` shows a **human-readable** run log
- To keep the **raw** agent stream for debugging: set `MILHOUSE_AGENT_OUTPUT_MODE=stream-json` (writes `.milhouse/out.stream.jsonl`)

### Reference docs

- `MILHOUSE_PLAN.md` - Detailed implementation plan
- `UI_RULES.md` - Milhouse-specific UI guidelines
- `GUM_TUI_RULES.md` - General gum/TUI design principles

## Key Files

- `README.md` - This file
- `TODO.md` - Task tracking
- `project-log.md` - Decision tracking and version history
- `MILHOUSE_PLAN.md` - Detailed implementation plan and analysis
- `UI_RULES.md` - UI design rules for Milhouse
- `GUM_TUI_RULES.md` - General gum/TUI design principles

## Status

✅ **Runnable** - `scripts/milhouse.sh` is implemented; use `install.sh` to install into other repos.
