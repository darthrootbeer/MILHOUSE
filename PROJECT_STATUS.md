# Project Status

## Current Phase

✅ **Runnable**

Milhouse is runnable end-to-end via `scripts/milhouse.sh`, with `install.sh` available to install it into another repo.

## Progress Overview

### ✅ Completed

- Project structure created
- Implementation plan documented (MILHOUSE_PLAN.md)
- UI design rules established (UI_RULES.md, GUM_TUI_RULES.md)
- Architecture decisions made (heuristic-based, single script, git as audit trail)
- Core loop implemented (`scripts/milhouse.sh`)
- Rotation heuristics implemented (fixed + time/files/commits)
- Gutter detection implemented
- UX polish implemented (gum UI + fallback, clearer errors, progress/status)
- Installer added (`install.sh`)
- Human-readable run log (`.milhouse/out.txt`) with optional raw stream (`.milhouse/out.stream.jsonl`)

### 🚧 In Progress

- None currently

### 📋 Planned

#### Testing & Documentation

- [ ] Create test task file example
- [ ] Expand usage documentation in README
- [ ] Document rotation/gutter heuristics and tuning

## Key Decisions

1. **Heuristic-based rotation** instead of precise token tracking
2. **Single script architecture** instead of multiple modules
3. **Git as audit trail** instead of separate log files
4. **Gum for UI** with graceful fallback

## Dependencies

- `bash` (required)
- `git` (required)
- `gum` (optional, for enhanced UI)
- `cursor-agent` CLI (required for actual usage, not for development)

## Next Steps

1. Finish the remaining documentation tasks (README usage + heuristics)
2. Add a sample task file for testing/demo
3. Keep the changelog updated as behavior changes

## Notes

- Reference implementation available in `ralph-wiggum-cursor/` subdirectory
- Goal: 80% of Ralph's functionality with 20% of the complexity
