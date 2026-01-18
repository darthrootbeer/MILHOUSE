# Milhouse: Simplified Autonomous Development Loop

## Deep Analysis of Ralph's Complexity

### What Ralph Does Well
1. **Core loop concept** - Fresh context per iteration ✅
2. **State in files** - Progress persists across rotations ✅
3. **Guardrails/learning** - Prevents repeated mistakes ✅
4. **Checkbox completion** - Clear success criteria ✅

### Where Ralph Gets Complex

#### 1. Stream Parsing Complexity
**Current approach:**
- Real-time JSON parsing with `jq` on every line
- Tracks: `BYTES_READ`, `BYTES_WRITTEN`, `ASSISTANT_CHARS`, `SHELL_OUTPUT_CHARS`
- Complex state management across tool calls
- Named pipes (`fifo`) for signaling
- ~300 lines of parsing logic

**Why complex:** Requires parsing Cursor's JSON stream format, tracking multiple variables, managing temp files for gutter detection, handling edge cases.

#### 2. Multiple Script Architecture
**Current:** 6 scripts with shared state
- `ralph-common.sh` (~680 lines)
- `ralph-setup.sh` (~409 lines)
- `ralph-loop.sh` (~197 lines)
- `ralph-once.sh` (~227 lines)
- `stream-parser.sh` (~304 lines)
- `init-ralph.sh` (~203 lines)

**Why complex:** Shared functions, state management, different entry points with overlapping logic.

#### 3. Token Tracking Precision
**Current:** Tries to be precise
- Reads actual file sizes from JSON
- Calculates `tokens = bytes / 4`
- Tracks every read/write/assistant/shell operation
- Logs detailed breakdowns

**Why complex:** Requires JSON parsing, assumes 4 chars/token ratio, tracks multiple dimensions.

#### 4. Gutter Detection
**Current:** Heuristic-based with temp files
- Tracks command failures in temp file
- Tracks file writes with timestamps
- Checks patterns after each operation
- Cross-platform temp file handling

**Why complex:** State persistence across operations, time-based checks, pattern matching.

## Simplification Strategy

### Core Insight
**We don't need perfect token tracking to achieve the same result.**

Ralph's goal: Rotate context before it fills up. We can achieve this with:
- **Simpler heuristics** instead of precise counting
- **Post-iteration analysis** instead of real-time parsing
- **Single script** with clear flow instead of multiple scripts

### Simplifications

#### 1. Replace Stream Parsing with Post-Iteration Analysis

**Instead of:** Real-time JSON stream parsing with `jq`

**Do:** 
- Run cursor-agent normally (capture output to file)
- After iteration completes, analyze what happened
- Use simpler heuristics: iteration duration, file count, git commit count

**Benefits:**
- No JSON parsing complexity
- No named pipes or signaling
- Simpler error handling
- Works with any cursor-agent output format

**Note:** We'll still use `gum` for pretty interactive UI (optional but recommended)

#### 2. Heuristic-Based Token Estimation

**Instead of:** Precise byte counting `tokens = (bytes_read + bytes_written + ...) / 4`

**Do:**
- **Time-based rotation:** If iteration runs >30 minutes, assume context is filling
- **File-based rotation:** If >50 files read/modified, rotate
- **Commit-based rotation:** After N commits in one iteration, rotate
- **Simple counter:** Track iteration number, rotate every N iterations

**Benefits:**
- No JSON parsing
- Simple counters
- Works regardless of cursor-agent format changes

#### 3. Single Script with Modes

**Instead of:** 6 scripts with shared functions

**Do:**
- **One script:** `milhouse.sh`
- **Modes:** `--once`, `--loop`, `--setup` (or just positional args)
- **All logic in one file** (easier to understand, fewer dependencies)

**Benefits:**
- Easier to reason about
- Single source of truth
- Simpler debugging

#### 4. Simplified Gutter Detection

**Instead of:** Temp files, timestamp tracking, pattern matching

**Do:**
- **Check git log:** If same error message appears 3x, gutter
- **Check task file:** If no checkbox changed in 2 iterations, gutter
- **Time limit:** If iteration runs >1 hour, assume stuck
- **Manual detection:** Let agent signal `<milhouse>GUTTER</milhouse>`

**Benefits:**
- Uses existing git state
- Simpler checks
- Less state to manage

#### 5. Simpler State Files

**Instead of:** Multiple state files with complex formats

**Do:**
- `.milhouse/iteration` - Just a number
- `.milhouse/progress.md` - Simple markdown (agent writes)
- `.milhouse/guardrails.md` - Simple markdown (agent writes)
- No separate activity/errors logs - use git log for history

**Benefits:**
- Fewer files to manage
- Git becomes the audit trail
- Simpler mental model

## Milhouse Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  MILHOUSE_TASK.md (checkboxes [ ] → [x])                   │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  milhouse.sh [--once|--loop|--setup]                       │
│  - Reads task and state                                      │
│  - Builds prompt                                             │
│  - Runs: cursor-agent -p "prompt" > .milhouse/out.txt      │
│  - Waits for completion                                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Post-iteration analysis                                     │
│  - Check completion (all [x]?)                              │
│  - Heuristic: should rotate?                                │
│    • Time > 30 min → ROTATE                                 │
│    • Files touched > 50 → ROTATE                            │
│    • Iteration # mod 5 == 0 → ROTATE (every 5 iterations)   │
│  - Check gutter:                                            │
│    • Same error 3x in git log → GUTTER                      │
│    • No progress 2 iterations → GUTTER                      │
│    • Agent signaled → GUTTER                                 │
└─────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        ▼                                   ▼
┌──────────────────┐              ┌──────────────────┐
│  Continue loop   │              │  Stop & report   │
│  - Increment .milhouse/iteration│  - Gutter detected│
│  - Fresh context                 │  - Check guardrails│
└──────────────────┘              └──────────────────┘
```

## Implementation Plan

### Phase 1: Core Loop (Simplest Version)

**Goal:** Get basic loop working without any token tracking

**Features:**
- Read `MILHOUSE_TASK.md` with checkboxes
- Run cursor-agent with prompt
- Check completion after each iteration
- Rotate every N iterations (fixed, e.g., 5)
- Single script: `milhouse.sh`

**State files:**
- `.milhouse/iteration` - counter
- `.milhouse/progress.md` - agent writes progress
- `.milhouse/guardrails.md` - agent writes signs

**No:**
- Token tracking
- Stream parsing
- Gutter detection
- Multiple scripts

### Phase 2: Smart Rotation

**Add:** Heuristic-based rotation
- Time-based (>30 min)
- File count-based (>50 files touched)
- Commit count-based (>10 commits)

**How:**
- After each iteration, check git diff stats
- Count files changed: `git diff --stat | wc -l`
- Check iteration duration: `date` before/after

### Phase 3: Gutter Detection

**Add:** Simple gutter checks
- Check git log for repeated errors
- Check if task file unchanged for 2 iterations
- Agent can signal `<milhouse>GUTTER</milhouse>`

**How:**
- `git log --oneline -20` - look for patterns
- Compare `MILHOUSE_TASK.md` hash between iterations
- Grep agent output for sigil

### Phase 4: Polish

**Add:**
- Interactive setup with `gum` for beautiful UI (falls back to simple prompts if not installed)
- Better error messages
- Progress reporting with nice formatting
- Help text
- Status indicators and spinners

## Comparison: Ralph vs Milhouse

| Feature | Ralph | Milhouse |
|---------|-------|----------|
| **Token Tracking** | Real-time JSON parsing | Heuristic-based |
| **Scripts** | 6 files, ~2000 lines | 1 file, ~300 lines |
| **Complexity** | High (JSON, pipes, state) | Low (simple checks) |
| **Dependencies** | jq, gum (optional) | gum (optional, for pretty UI) |
| **Rotation** | Precise (80k tokens) | Heuristic (time/files/iterations) |
| **Gutter Detection** | Temp files, timestamps | Git log, simple checks |
| **State Files** | 5 files | 3 files |
| **Setup** | Install script | Copy one script |
| **Maintenance** | Complex | Simple |

## Key Simplifications

### 1. No Real-Time Parsing
✅ Run agent, wait for completion, then analyze  
❌ Don't parse JSON stream line-by-line

### 2. Heuristics Over Precision
✅ "If iteration runs >30 min or touches >50 files, rotate"  
❌ Don't count bytes and divide by 4

### 3. Git as Audit Trail
✅ Use `git log` and `git diff` for analysis  
❌ Don't maintain separate activity/error logs

### 4. Single Script (with Optional Gum UI)
✅ One file with clear flow  
✅ Use `gum` for beautiful interactive UI (optional)  
❌ Don't split across multiple scripts with shared state

### 5. Simpler State
✅ Iteration counter + 2 markdown files  
❌ Don't track activity logs, error logs, temp files

## Questions to Answer

1. **Will heuristic rotation work as well?**
   - Test: Run same task with both systems
   - Measure: Do we rotate too early/late?
   - Adjust: Tune thresholds based on results

2. **Is simpler gutter detection sufficient?**
   - Test: Known stuck scenarios
   - Compare: Does it catch issues Ralph caught?
   - Improve: Add more checks if needed

3. **Can we avoid stream parsing entirely?**
   - Test: Run cursor-agent and analyze after
   - Verify: Do we miss critical signals?
   - Fallback: Can add minimal stream watching if needed

## Next Steps

1. **Create `milhouse.sh`** - Single script with basic loop
2. **Test with simple task** - Verify core concept works
3. **Add heuristic rotation** - Test rotation triggers
4. **Add gutter detection** - Test stuck detection
5. **Document and polish** - Make it production-ready

## Success Criteria

Milhouse succeeds if:
- ✅ Achieves same result as Ralph (autonomous development with context rotation)
- ✅ Simpler to understand and maintain
- ✅ Fewer dependencies
- ✅ Easier to debug
- ✅ Works with same task format

**Goal:** 80% of the functionality with 20% of the complexity.
