# TODO

## Active

## In Progress

## Completed

## Phase 1: Core Loop

- [x] [A1B2C3](TODO/A1B2C3.md) - Create milhouse.sh script skeleton with shebang, error handling, and mode detection
- [x] [D4E5F6](TODO/D4E5F6.md) - Implement task file reading: parse MILHOUSE_TASK.md and extract checkboxes
- [x] [G7H8I9](TODO/G7H8I9.md) - Implement checkbox completion checking: count [ ] vs [x] in task file
- [x] [J0K1L2](TODO/J0K1L2.md) - Build prompt template: create Milhouse instruction prompt for agent
- [x] [M3N4O5](TODO/M3N4O5.md) - Implement state file management: create .milhouse/ directory and initialize files
- [x] [P6Q7R8](TODO/P6Q7R8.md) - Implement iteration counter: read/write .milhouse/iteration file
- [x] [S9T0U1](TODO/S9T0U1.md) - Implement cursor-agent execution: run agent with prompt and capture output
- [x] [V2W3X4](TODO/V2W3X4.md) - Implement fixed rotation logic: rotate every N iterations (default 5)
- [x] [Y5Z6A7](TODO/Y5Z6A7.md) - Implement main loop: iteration control flow with completion checking
- [x] [B8C9D0](TODO/B8C9D0.md) - Add --once mode: run single iteration then stop
- [x] [E1F2G3](TODO/E1F2G3.md) - Add --loop mode: run continuous loop until completion or max iterations
- [x] [H4I5J6](TODO/H4I5J6.md) - Add basic error handling: check prerequisites (git, cursor-agent, task file)

## Phase 2: Smart Rotation

- [x] [K7L8M9](TODO/K7L8M9.md) - Implement time-based rotation: measure iteration duration, rotate if >30 minutes
- [x] [N0O1P2](TODO/N0O1P2.md) - Implement file count-based rotation: count files changed via git diff, rotate if >50
- [x] [Q3R4S5](TODO/Q3R4S5.md) - Implement commit count-based rotation: count commits in iteration, rotate if >10
- [x] [T6U7V8](TODO/T6U7V8.md) - Integrate rotation heuristics: combine all heuristics with OR logic
- [x] [W9X0Y1](TODO/W9X0Y1.md) - Add rotation reporting: log why rotation occurred (time/files/commits/fixed)

## Phase 3: Gutter Detection

- [x] [Z2A3B4](TODO/Z2A3B4.md) - Implement git log error pattern detection: scan last 20 commits for repeated errors
- [x] [C5D6E7](TODO/C5D6E7.md) - Implement task file change detection: compare MILHOUSE_TASK.md hash between iterations
- [x] [F8G9H0](TODO/F8G9H0.md) - Implement time limit detection: if iteration >1 hour, trigger gutter
- [x] [I1J2K3](TODO/I1J2K3.md) - Implement agent signal detection: grep output for <milhouse>GUTTER</milhouse>
- [x] [L4M5N6](TODO/L4M5N6.md) - Integrate gutter detection: combine all checks, stop loop if gutter detected

## Phase 4: Polish

- [x] [O7P8Q9](TODO/O7P8Q9.md) - Add gum detection: check if gum installed, fallback to plain prompts
- [x] [R0S1T2](TODO/R0S1T2.md) - Implement interactive setup with gum: model selection, options, confirmation
- [x] [U3V4W5](TODO/U3V4W5.md) - Improve error messages: descriptive errors with actionable guidance per UI_RULES.md
- [ ] [X6Y7Z8](TODO/X6Y7Z8.md) - Add progress reporting: show iteration number, criteria progress, status indicators
- [ ] [A9B0C1](TODO/A9B0C1.md) - Add help text: --help flag showing usage and options
- [ ] [D2E3F4](TODO/D2E3F4.md) - Add status indicators: use gum spinners for long operations
- [ ] [G5H6I7](TODO/G5H6I7.md) - Format output with gum style: consistent borders, colors, padding per GUM_TUI_RULES.md

## Testing & Documentation

- [ ] [J8K9L0](TODO/J8K9L0.md) - Create test task file: MILHOUSE_TASK_EXAMPLE.md with sample checkboxes
- [ ] [M1N2O3](TODO/M1N2O3.md) - Test Phase 1: verify basic loop works with simple task
- [ ] [P4Q5R6](TODO/P4Q5R6.md) - Test Phase 2: verify rotation triggers work correctly
- [ ] [S7T8U9](TODO/S7T8U9.md) - Test Phase 3: verify gutter detection catches stuck scenarios
- [ ] [V0W1X2](TODO/V0W1X2.md) - Test Phase 4: verify gum UI and fallback both work
- [ ] [Y3Z4A5](TODO/Y3Z4A5.md) - Create usage documentation: README section on how to use milhouse.sh
- [ ] [B6C7D8](TODO/B6C7D8.md) - Document heuristics: explain rotation thresholds and how to tune them
