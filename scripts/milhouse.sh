#!/bin/bash
# Milhouse: Simplified Autonomous Development Loop
#
# A streamlined version of Ralph Wiggum for Cursor, with heuristic-based
# context rotation and simplified state management.
#
# Usage:
#   ./milhouse.sh [--once|--loop|--setup] [workspace]
#   ./milhouse.sh --help
#
# Modes:
#   --once   Run a single iteration then stop (default for testing)
#   --loop   Run continuous loop until completion or max iterations (default)
#   --setup  Interactive setup for first-time configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default model (can be overridden via environment or setup)
MODEL="${MILHOUSE_MODEL:-opus-4.5-thinking}"

# Default rotation interval (fixed rotation in Phase 1)
ROTATION_INTERVAL="${MILHOUSE_ROTATION_INTERVAL:-5}"

# Maximum iterations before stopping
MAX_ITERATIONS="${MILHOUSE_MAX_ITERATIONS:-20}"

# =============================================================================
# GUM DETECTION (Phase 4: Polish)
# =============================================================================

# Check if gum is installed
# Returns: 0 if gum is available, 1 if not
check_gum() {
  command -v gum &> /dev/null
}

# Set HAS_GUM flag based on gum availability
# Called early in script initialization
HAS_GUM="false"
if check_gum; then
  HAS_GUM="true"
fi

# =============================================================================
# OUTPUT HELPERS (Phase 4: Polish)
# =============================================================================

# Display an error message with formatting
# Args: main_message, details (optional)
show_error() {
  local message="$1"
  local details="${2:-}"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    if [[ -n "$details" ]]; then
      gum style --foreground 1 --border double --padding "0 1" \
        "Error: $message" "" "$details"
    else
      gum style --foreground 1 --border double --padding "0 1" \
        "Error: $message"
    fi
  else
    echo -e "\033[31m═══════════════════════════════════════════════════════════════════\033[0m" >&2
    echo -e "\033[31mError: $message\033[0m" >&2
    if [[ -n "$details" ]]; then
      echo "" >&2
      echo -e "$details" >&2
    fi
    echo -e "\033[31m═══════════════════════════════════════════════════════════════════\033[0m" >&2
  fi
}

# Display a success message with formatting
# Args: message
show_success() {
  local message="$1"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --foreground 10 --bold "✓ $message"
  else
    echo -e "\033[32m✓ $message\033[0m"
  fi
}

# Display a warning message with formatting
# Args: message
show_warning() {
  local message="$1"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --foreground 3 "⚠ $message"
  else
    echo -e "\033[33m⚠ $message\033[0m"
  fi
}

# Display an info message with formatting
# Args: message
show_info() {
  local message="$1"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --foreground 12 "$message"
  else
    echo -e "\033[34m$message\033[0m"
  fi
}

# Display progress information with formatting
# Args: iteration, done_count, total, remaining
show_progress() {
  local iteration="$1"
  local done_count="$2"
  local total="$3"
  local remaining="$4"
  
  local progress_text="Iteration $iteration: $done_count/$total criteria complete ($remaining remaining)"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --border normal --padding "0 1" --border-foreground 8 "$progress_text"
  else
    echo "┌──────────────────────────────────────────────────────────────────┐"
    printf "│ %-66s │\n" "$progress_text"
    echo "└──────────────────────────────────────────────────────────────────┘"
  fi
}

# Display a header with consistent styling
# Args: title, [color_code] (optional: 10=success, 1=error, 3=warning, 12=info)
show_header() {
  local title="$1"
  local color="${2:-212}"  # Default to accent color
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --border double --padding "0 2" --border-foreground "$color" "$title"
  else
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    printf "║  %-64s ║\n" "$title"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
  fi
}

# Display a section divider with title
# Args: title
show_section() {
  local title="$1"
  
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --border normal --padding "0 1" --border-foreground 8 "$title"
  else
    echo "┌───────────────────────────────────────────────────────────────────┐"
    printf "│ %-65s │\n" "$title"
    echo "└───────────────────────────────────────────────────────────────────┘"
  fi
}

# =============================================================================
# TODO.md → MILHOUSE_TASK.md WORKFLOW (Recommendation #3)
# =============================================================================

# Cross-platform sed -i helper
sedi() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# List unchecked TODO items from TODO.md (best-effort).
# Output: one item per line (the full TODO line).
list_unchecked_todo_items() {
  local workspace="$1"
  local todo_file="$workspace/TODO.md"
  
  if [[ ! -f "$todo_file" ]]; then
    return 1
  fi
  
  # Only count real list-item checkboxes (not prose).
  grep -E '^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+' "$todo_file" || true
}

# Create MILHOUSE_TASK.md from selected TODO.md lines.
# Args: workspace, selected_lines (newline-separated)
create_task_from_todo_selection() {
  local workspace="$1"
  local selected_lines="$2"
  local task_file="$workspace/MILHOUSE_TASK.md"
  
  if [[ -z "$selected_lines" ]]; then
    show_warning "No TODO items selected. Not creating MILHOUSE_TASK.md."
    return 1
  fi
  
  {
    echo "# Milhouse task run"
    echo ""
    echo "## Goal"
    echo "Complete the selected TODO items from this repo."
    echo ""
    echo "## Completion criteria"
    # Convert TODO lines into plain Milhouse checklist items.
    # Example TODO line:
    # - [ ] [O7P8Q9](TODO/O7P8Q9.md) - Add gum detection...
    # becomes:
    # - [ ] [O7P8Q9](TODO/O7P8Q9.md) - Add gum detection...
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local item
      item="$(echo "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+//')"
      echo "- [ ] $item"
    done <<< "$selected_lines"
    echo ""
    echo "## Done"
    echo "When all checkboxes above are \`[x]\`, output:"
    echo "\`<milhouse>COMPLETE</milhouse>\`"
    echo ""
  } > "$task_file"
  
  show_success "Created MILHOUSE_TASK.md from TODO.md selection"
  return 0
}

# If a checkbox item is marked complete in MILHOUSE_TASK.md, mark it complete in TODO.md too.
# Matching is primarily by stable id token: [A1B2C3], [O7P8Q9], etc.
sync_task_progress_to_todo() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  local todo_file="$workspace/TODO.md"
  
  [[ -f "$task_file" ]] || return 0
  [[ -f "$todo_file" ]] || return 0
  
  # Extract completed IDs from MILHOUSE_TASK.md:
  # - [x] [ID] ...
  local ids
  ids="$(grep -E '^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+\[[A-Za-z0-9]+\]' "$task_file" \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+\[([A-Za-z0-9]+)\].*$/\1/' \
    | sort -u)"
  
  if [[ -z "$ids" ]]; then
    return 0
  fi
  
  # For each completed ID, flip the matching TODO line to [x].
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    # Example TODO line:
    # - [ ] [ID](...) - ...
    # becomes:
    # - [x] [ID](...) - ...
    sedi -E "s/^([[:space:]]*[-*][[:space:]]*)\\[ \\] ([[:space:]]*\\[${id}\\])/\1[x] \2/" "$todo_file" || true
  done <<< "$ids"
}

# Ensure MILHOUSE_TASK.md exists. If missing, ask what Milhouse should do.
# For your preference, this only runs when the task file is missing.
ensure_task_file() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  
  if [[ -f "$task_file" ]]; then
    return 0
  fi
  
  show_header "Milhouse setup: choose what to work on" 12
  echo ""
  
  local choice=""
  if [[ "$HAS_GUM" == "true" ]]; then
    choice="$(gum choose --header "What should Milhouse work on?" \
      "Use TODO.md (pick tasks)" \
      "Custom goal (write a new task)")"
  else
    echo "What should Milhouse work on?"
    echo "  1) Use TODO.md (pick tasks)"
    echo "  2) Custom goal (write a new task)"
    read -rp "Choice [1-2]: " choice_num
    if [[ "$choice_num" == "1" ]]; then
      choice="Use TODO.md (pick tasks)"
    else
      choice="Custom goal (write a new task)"
    fi
  fi
  
  if [[ "$choice" == "Use TODO.md (pick tasks)" ]]; then
    local items
    items="$(list_unchecked_todo_items "$workspace")"
    if [[ -z "$items" ]]; then
      show_error "No unchecked TODO items found" \
        "Milhouse looked for unchecked items in:
  $workspace/TODO.md

Fix: Add tasks in TODO.md using this format:
  - [ ] My next task"
      return 1
    fi
    
    local selected=""
    if [[ "$HAS_GUM" == "true" ]]; then
      # Multi-select checklist
      selected="$(printf "%s\n" "$items" | gum choose --no-limit --header "Select TODO items for this run:")"
    else
      show_info "Paste the TODO lines you want Milhouse to work on (end with an empty line):"
      local line
      while IFS= read -r line; do
        [[ -z "$line" ]] && break
        selected="${selected}${line}"$'\n'
      done
    fi
    
    create_task_from_todo_selection "$workspace" "$selected"
    return $?
  fi
  
  # Custom goal path (minimal scaffold; user can refine later).
  local goal=""
  if [[ "$HAS_GUM" == "true" ]]; then
    goal="$(gum input --header "Describe what Milhouse should accomplish:" --placeholder "e.g., Improve the README and add a test task example")"
  else
    read -rp "Describe what Milhouse should accomplish: " goal
  fi
  
  if [[ -z "$goal" ]]; then
    show_warning "No goal provided. Not creating MILHOUSE_TASK.md."
    return 1
  fi
  
  {
    echo "# Milhouse task run"
    echo ""
    echo "## Goal"
    echo "$goal"
    echo ""
    echo "## Completion criteria"
    echo "- [ ] Define the concrete completion criteria for this goal"
    echo ""
    echo "## Done"
    echo "When all checkboxes above are \`[x]\`, output:"
    echo "\`<milhouse>COMPLETE</milhouse>\`"
    echo ""
  } > "$task_file"
  
  show_success "Created MILHOUSE_TASK.md (custom goal scaffold)"
  return 0
}

# =============================================================================
# OUT.TXT VERBOSE LOGGING (Milhouse journal + agent output)
# =============================================================================

# Ensure out.txt exists with a run header (once per run).
# Args: workspace
init_out_log() {
  local workspace="$1"
  local output_file="$workspace/.milhouse/out.txt"
  mkdir -p "$workspace/.milhouse"
  if [[ ! -f "$output_file" ]]; then
    {
      echo "═══════════════════════════════════════════════════════════════════"
      echo "Milhouse run log (human-readable)"
      echo "Workspace: $workspace"
      echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "═══════════════════════════════════════════════════════════════════"
      echo "Note: raw agent stream is also saved to: .milhouse/out.stream.jsonl"
      echo ""
    } > "$output_file"
  fi
}

# Find a python interpreter (prefer python3).
detect_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    echo "python"
    return 0
  fi
  echo ""
  return 1
}

# Convert cursor-agent stream-json into readable log lines.
# Reads from stdin; writes cleaned text to stdout.
clean_cursor_agent_stream() {
  local python_bin
  python_bin="$(detect_python)"
  if [[ -z "$python_bin" ]]; then
    # No python available; passthrough raw stream.
    cat
    return 0
  fi

  "$python_bin" -c '
import sys, json

last = ""

def emit(s: str):
  global last
  s = (s or "").strip("\n")
  if not s:
    return
  if s == last:
    return
  last = s
  sys.stdout.write(s)
  if not s.endswith("\n"):
    sys.stdout.write("\n")
  sys.stdout.flush()

for line in sys.stdin:
  raw = line.rstrip("\n")
  if not raw.strip():
    continue
  try:
    obj = json.loads(raw)
  except Exception:
    # Keep non-JSON lines (often useful errors), but avoid spammy whitespace.
    emit(raw)
    continue

  t = obj.get("type")
  if t != "assistant":
    continue

  # Heuristic: only print the "final" assistant message, not partial fragments.
  # The partial fragments tend to be tiny; the final tends to include model_call_id.
  if not obj.get("model_call_id"):
    continue

  msg = obj.get("message") or {}
  content = msg.get("content") or []
  parts = []
  for c in content:
    if isinstance(c, dict) and c.get("type") == "text" and isinstance(c.get("text"), str):
      parts.append(c["text"])
  text = "".join(parts).strip()
  if text:
    emit(text)
' 2>/dev/null
}

# Append a timestamped line to out.txt.
# Args: workspace, message
log_out() {
  local workspace="$1"
  local message="$2"
  local output_file="$workspace/.milhouse/out.txt"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  mkdir -p "$workspace/.milhouse"
  printf "[%s] %s\n" "$ts" "$message" >> "$output_file"
}

# Append a section header to out.txt.
# Args: workspace, title
log_out_section() {
  local workspace="$1"
  local title="$2"
  local output_file="$workspace/.milhouse/out.txt"
  mkdir -p "$workspace/.milhouse"
  {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "$title"
    echo "═══════════════════════════════════════════════════════════════════"
  } >> "$output_file"
}

# =============================================================================
# HELP TEXT
# =============================================================================

show_help() {
  cat << 'EOF'
Milhouse: Simplified Autonomous Development Loop

A streamlined autonomous development loop for Cursor with heuristic-based
context rotation. Runs agents to complete tasks defined in MILHOUSE_TASK.md.

USAGE
  ./milhouse.sh [mode] [workspace]

MODES
  --once        Run a single iteration then stop
  --loop        Run continuous loop until completion (default)
  --setup       Interactive setup for model and options
  --help        Show this help message

ARGUMENTS
  workspace     Path to project directory (default: current directory)

ENVIRONMENT VARIABLES
  MILHOUSE_MODEL              AI model to use (default: opus-4.5-thinking)
  MILHOUSE_MAX_ITERATIONS     Maximum iterations before stopping (default: 20)
  MILHOUSE_ROTATION_INTERVAL  Fixed rotation every N iterations (default: 5)

EXAMPLES
  ./milhouse.sh                              # Loop mode, current directory
  ./milhouse.sh --once                       # Single iteration, then stop
  ./milhouse.sh --loop /path/to/project      # Loop mode, specific project
  ./milhouse.sh --setup                      # Interactive configuration
  MILHOUSE_MODEL=sonnet-4 ./milhouse.sh      # Use specific model
  MILHOUSE_MAX_ITERATIONS=50 ./milhouse.sh   # Run up to 50 iterations

REQUIREMENTS
  - MILHOUSE_TASK.md: Task file with completion criteria (checkboxes)
  - Git repository: Initialized in the project directory
  - cursor-agent: CLI tool installed and in PATH

TASK FILE FORMAT
  Create MILHOUSE_TASK.md with checkboxes for completion criteria:

    ## Completion criteria
    - [ ] Implement feature X
    - [ ] Add tests for feature X
    - [ ] Update documentation

  Milhouse marks items [x] as they're completed.

For more information, see README.md
EOF
}

# =============================================================================
# FLAG PARSING
# =============================================================================

# Default mode is --loop if no mode specified
MODE="loop"
WORKSPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      MODE="once"
      shift
      ;;
    --loop)
      MODE="loop"
      shift
      ;;
    --setup)
      MODE="setup"
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    -*)
      show_error "Unknown option: $1" \
        "This flag is not recognized.

Valid options:
  --once   Run a single iteration then stop
  --loop   Run continuous loop until completion
  --setup  Interactive setup
  --help   Show usage information

Fix: Check your command and try again, or run:
  $0 --help"
      exit 1
      ;;
    *)
      # Positional argument = workspace
      if [[ -z "$WORKSPACE" ]]; then
        WORKSPACE="$1"
      else
        show_error "Multiple workspace arguments provided" \
          "You specified: '$WORKSPACE' and '$1'

Milhouse only accepts one workspace path.

Fix: Use only one workspace argument:
  $0 [--mode] /path/to/project

Example:
  $0 --loop ~/my-project"
        exit 1
      fi
      shift
      ;;
  esac
done

# =============================================================================
# WORKSPACE DETECTION
# =============================================================================

# Resolve workspace to absolute path
if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="$(pwd)"
elif [[ "$WORKSPACE" == "." ]]; then
  WORKSPACE="$(pwd)"
else
  # Convert relative path to absolute
  WORKSPACE="$(cd "$WORKSPACE" && pwd)"
fi

# =============================================================================
# PHASE 1: STATE FILE MANAGEMENT
# =============================================================================

# Initialize .milhouse/ directory structure and state files
# Args: workspace
init_state() {
  local workspace="$1"
  local milhouse_dir="$workspace/.milhouse"
  
  mkdir -p "$milhouse_dir"
  
  # Initialize iteration counter if missing
  if [[ ! -f "$milhouse_dir/iteration" ]]; then
    echo "0" > "$milhouse_dir/iteration"
  fi
  
  # Initialize progress.md if missing
  if [[ ! -f "$milhouse_dir/progress.md" ]]; then
    cat > "$milhouse_dir/progress.md" << 'EOF'
# Progress Log

> Updated by the agent after significant work.

---

## Session History

EOF
  fi
  
  # Initialize guardrails.md if missing
  if [[ ! -f "$milhouse_dir/guardrails.md" ]]; then
    cat > "$milhouse_dir/guardrails.md" << 'EOF'
# Milhouse Guardrails (Signs)

> Lessons learned from past failures. READ THESE BEFORE ACTING.

## Core Signs

### Sign: Read Before Writing
- **Trigger**: Before modifying any file
- **Instruction**: Always read the existing file first
- **Added after**: Core principle

### Sign: Test After Changes
- **Trigger**: After any code change
- **Instruction**: Run tests to verify nothing broke
- **Added after**: Core principle

### Sign: Commit Checkpoints
- **Trigger**: Before risky changes
- **Instruction**: Commit current working state first
- **Added after**: Core principle

---

## Learned Signs

EOF
  fi
}

# =============================================================================
# PHASE 1: TASK FILE READING
# =============================================================================

# Read MILHOUSE_TASK.md and extract checkbox information
# Args: workspace
# Returns: "total:done:remaining" via echo
read_task_file() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  
  if [[ ! -f "$task_file" ]]; then
    echo "0:0:0"  # Return empty counts if file doesn't exist
    return 1
  fi
  
  # Count all checkboxes (both [ ] and [x])
  # Matches: "- [ ]", "* [x]", "1. [ ]", etc.
  local total done_count
  total=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[(x| )\]' "$task_file" 2>/dev/null) || total=0
  done_count=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[x\]' "$task_file" 2>/dev/null) || done_count=0
  
  local remaining=$((total - done_count))
  echo "$total:$done_count:$remaining"
  return 0
}

# Check if task is complete
# Args: workspace
# Returns: "COMPLETE" or "INCOMPLETE:N" where N is remaining count
check_task_complete() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  
  if [[ ! -f "$task_file" ]]; then
    echo "NO_TASK_FILE"
    return 1
  fi
  
  # Count unchecked checkboxes
  # Matches: "- [ ]", "* [ ]", "1. [ ]", etc.
  local unchecked
  unchecked=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[ \]' "$task_file" 2>/dev/null) || unchecked=0
  
  if [[ "$unchecked" -eq 0 ]]; then
    echo "COMPLETE"
    return 0
  else
    echo "INCOMPLETE:$unchecked"
    return 0
  fi
}

# =============================================================================
# PHASE 1: ITERATION COUNTER
# =============================================================================

# Get current iteration number
# Args: workspace
# Returns: iteration number (default 0)
get_iteration() {
  local workspace="$1"
  local iteration_file="$workspace/.milhouse/iteration"
  
  if [[ -f "$iteration_file" ]]; then
    cat "$iteration_file"
  else
    echo "0"
  fi
}

# Set iteration number
# Args: workspace, iteration
set_iteration() {
  local workspace="$1"
  local iteration="$2"
  local milhouse_dir="$workspace/.milhouse"
  
  mkdir -p "$milhouse_dir"
  echo "$iteration" > "$milhouse_dir/iteration"
}

# Increment iteration and return new value
# Args: workspace
# Returns: new iteration number
increment_iteration() {
  local workspace="$1"
  local current=$(get_iteration "$workspace")
  local next=$((current + 1))
  set_iteration "$workspace" "$next"
  echo "$next"
}

# =============================================================================
# PHASE 2: SMART ROTATION - Time-Based Rotation
# =============================================================================

# Time-based rotation: rotate if iteration duration > threshold
# Args: duration_seconds (unix timestamp difference)
# Returns: 0 if should rotate, 1 if not
should_rotate_time() {
  local duration_seconds="${1:-0}"
  local threshold_seconds="${2:-1800}"  # Default 30 minutes = 1800 seconds
  
  if [[ $duration_seconds -gt $threshold_seconds ]]; then
    return 0  # Should rotate
  else
    return 1  # Should not rotate
  fi
}

# Track iteration start time
# Returns: unix timestamp
track_iteration_start() {
  date +%s
}

# Track iteration end time and calculate duration
# Args: start_time (unix timestamp)
# Returns: duration in seconds
calculate_iteration_duration() {
  local start_time="${1:-$(date +%s)}"
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  echo "$duration"
}

# =============================================================================
# PHASE 2: SMART ROTATION - File Count-Based Rotation
# =============================================================================

# Count files changed in current iteration
# Args: workspace (optional, defaults to current directory)
# Returns: number of files changed (0 if no changes or error)
count_files_changed() {
  local workspace="${1:-.}"
  local file_count=0
  
  # Change to workspace if provided
  if [[ "$workspace" != "." ]]; then
    cd "$workspace" || {
      echo "0"
      return
    }
  fi
  
  # Check if git repo exists
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "0"
    return
  fi
  
  # Count files changed (tracked files only)
  # Use --name-only to get just filenames, then count lines
  file_count=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
  
  # Handle empty diff (returns 0 or empty)
  if [[ -z "$file_count" ]] || [[ "$file_count" == "0" ]]; then
    echo "0"
  else
    echo "$file_count"
  fi
}

# File count-based rotation: rotate if files changed > threshold
# Args: file_count (number of files changed)
# Returns: 0 if should rotate, 1 if not
should_rotate_files() {
  local file_count="${1:-0}"
  local threshold="${2:-50}"  # Default 50 files
  
  if [[ $file_count -gt $threshold ]]; then
    return 0  # Should rotate
  else
    return 1  # Should not rotate
  fi
}

# =============================================================================
# PHASE 2: SMART ROTATION - Commit Count-Based Rotation
# =============================================================================

# Track commit count before iteration
# Args: workspace (optional, defaults to current directory)
# Returns: total commit count from HEAD
track_commits_start() {
  local workspace="${1:-.}"
  local commit_count=0
  
  # Change to workspace if provided
  if [[ "$workspace" != "." ]]; then
    cd "$workspace" || echo "0"
    return
  fi
  
  # Check if git repo exists
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "0"
    return
  fi
  
  # Get total commit count
  commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
  echo "$commit_count"
}

# Calculate commits made during iteration
# Args: commit_count_start (number before iteration)
#       workspace (optional, defaults to current directory)
# Returns: number of new commits
count_commits_in_iteration() {
  local commit_count_start="${1:-0}"
  local workspace="${2:-.}"
  local commit_count_end=0
  local commit_diff=0
  
  # Change to workspace if provided
  if [[ "$workspace" != "." ]]; then
    cd "$workspace" || echo "0"
    return
  fi
  
  # Check if git repo exists
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "0"
    return
  fi
  
  # Get current commit count
  commit_count_end=$(git rev-list --count HEAD 2>/dev/null || echo "0")
  
  # Calculate difference
  commit_diff=$((commit_count_end - commit_count_start))
  
  # Ensure non-negative
  if [[ $commit_diff -lt 0 ]]; then
    commit_diff=0
  fi
  
  echo "$commit_diff"
}

# Commit count-based rotation: rotate if commits > threshold
# Args: commit_count (number of commits in iteration)
# Returns: 0 if should rotate, 1 if not
should_rotate_commits() {
  local commit_count="${1:-0}"
  local threshold="${2:-10}"  # Default 10 commits
  
  if [[ $commit_count -gt $threshold ]]; then
    return 0  # Should rotate
  else
    return 1  # Should not rotate
  fi
}

# =============================================================================
# PHASE 1: FIXED ROTATION (required for integration)
# =============================================================================

# Fixed rotation: rotate every N iterations
# Args: iteration (current iteration number)
#       rotate_interval (default 5)
# Returns: 0 if should rotate, 1 if not
should_rotate_fixed() {
  local iteration="${1:-0}"
  local rotate_interval="${2:-5}"  # Default every 5 iterations
  
  # Rotate if iteration > 0 and iteration % interval == 0
  if [[ $iteration -gt 0 ]] && [[ $((iteration % rotate_interval)) -eq 0 ]]; then
    return 0  # Should rotate
  else
    return 1  # Should not rotate
  fi
}

# =============================================================================
# PHASE 2: SMART ROTATION - Integration and Reporting
# =============================================================================

# Combined rotation check: returns rotation reason if any heuristic triggers
# Args: duration_seconds (iteration duration)
#       file_count (files changed)
#       commit_count (commits in iteration)
#       iteration (current iteration number)
#       rotate_interval (default 5)
# Returns: rotation reason string (empty if no rotation needed)
#          Format: "time|files|commits|fixed" with metric details
should_rotate() {
  local duration_seconds="${1:-0}"
  local file_count="${2:-0}"
  local commit_count="${3:-0}"
  local iteration="${4:-0}"
  local rotate_interval="${5:-5}"
  local time_threshold="${6:-1800}"  # 30 minutes
  local file_threshold="${7:-50}"    # 50 files
  local commit_threshold="${8:-10}"  # 10 commits
  local reason=""
  
  # Check time-based rotation
  if should_rotate_time "$duration_seconds" "$time_threshold"; then
    local minutes=$((duration_seconds / 60))
    reason="time (${minutes} min > $((time_threshold / 60)) min)"
    echo "$reason"
    return 0
  fi
  
  # Check file count-based rotation
  if should_rotate_files "$file_count" "$file_threshold"; then
    reason="files (${file_count} files > ${file_threshold} files)"
    echo "$reason"
    return 0
  fi
  
  # Check commit count-based rotation
  if should_rotate_commits "$commit_count" "$commit_threshold"; then
    reason="commits (${commit_count} commits > ${commit_threshold} commits)"
    echo "$reason"
    return 0
  fi
  
  # Check fixed rotation
  if should_rotate_fixed "$iteration" "$rotate_interval"; then
    reason="fixed (iteration ${iteration} % ${rotate_interval} == 0)"
    echo "$reason"
    return 0
  fi
  
  # No rotation needed
  echo ""
  return 1
}

# Log rotation reason in a clear format
# Args: rotation_reason (string from should_rotate())
log_rotation_reason() {
  local reason="${1:-}"
  
  if [[ -n "$reason" ]]; then
    show_info "Rotation triggered: $reason"
  fi
}

# Context “health” indicator (green/yellow/red) to show how close we are to a refresh.
# This is a proxy for “tokens left”, based on Milhouse’s heuristics.
# Args: duration_seconds, file_count, commit_count, iteration, rotate_interval
get_context_health_emoji() {
  local duration_seconds="${1:-0}"
  local file_count="${2:-0}"
  local commit_count="${3:-0}"
  local iteration="${4:-0}"
  local rotate_interval="${5:-5}"
  
  local time_threshold=1800   # 30 min
  local file_threshold=50
  local commit_threshold=10
  
  # Ratios in percent (0-100+)
  local time_pct=$(( duration_seconds * 100 / time_threshold ))
  local file_pct=$(( file_count * 100 / file_threshold ))
  local commit_pct=$(( commit_count * 100 / commit_threshold ))
  
  local iter_pos=0
  local iter_pct=0
  if [[ "$rotate_interval" -gt 0 ]]; then
    iter_pos=$(( ( (iteration - 1) % rotate_interval ) + 1 ))
    iter_pct=$(( iter_pos * 100 / rotate_interval ))
  fi
  
  # Max pct of all signals
  local max_pct=$time_pct
  if [[ $file_pct -gt $max_pct ]]; then max_pct=$file_pct; fi
  if [[ $commit_pct -gt $max_pct ]]; then max_pct=$commit_pct; fi
  if [[ $iter_pct -gt $max_pct ]]; then max_pct=$iter_pct; fi
  
  if [[ $max_pct -lt 60 ]]; then
    echo "🟢"
  elif [[ $max_pct -lt 85 ]]; then
    echo "🟡"
  else
    echo "🔴"
  fi
}

# Return a single “token budget” status line (emoji + estimates + guidance).
# This is heuristic-based (Milhouse does not parse exact token counts).
# Args: duration_seconds, file_count, commit_count, iteration, rotate_interval
get_token_budget_status_line() {
  local duration_seconds="${1:-0}"
  local file_count="${2:-0}"
  local commit_count="${3:-0}"
  local iteration="${4:-0}"
  local rotate_interval="${5:-5}"
  
  local time_threshold=1800   # 30 min
  local file_threshold=50
  local commit_threshold=10
  local token_capacity=80000  # Ralph-ish ballpark; heuristic display only
  
  local time_pct=$(( duration_seconds * 100 / time_threshold ))
  local file_pct=$(( file_count * 100 / file_threshold ))
  local commit_pct=$(( commit_count * 100 / commit_threshold ))
  
  local iter_pos=0
  local iter_pct=0
  if [[ "$rotate_interval" -gt 0 ]]; then
    iter_pos=$(( ( (iteration - 1) % rotate_interval ) + 1 ))
    iter_pct=$(( iter_pos * 100 / rotate_interval ))
  fi
  
  local max_pct=$time_pct
  if [[ $file_pct -gt $max_pct ]]; then max_pct=$file_pct; fi
  if [[ $commit_pct -gt $max_pct ]]; then max_pct=$commit_pct; fi
  if [[ $iter_pct -gt $max_pct ]]; then max_pct=$iter_pct; fi
  if [[ $max_pct -lt 0 ]]; then max_pct=0; fi
  if [[ $max_pct -gt 100 ]]; then max_pct=100; fi
  
  local emoji
  emoji="$(get_context_health_emoji "$duration_seconds" "$file_count" "$commit_count" "$iteration" "$rotate_interval")"
  
  local used=$(( token_capacity * max_pct / 100 ))
  local remaining=$(( token_capacity - used ))
  if [[ $remaining -lt 0 ]]; then remaining=0; fi
  
  local note=""
  if [[ $max_pct -ge 85 ]]; then
    note="token reset will occur soon (refresh threshold approaching)"
  elif [[ $max_pct -ge 60 ]]; then
    note="token budget mid-way (keep changes focused)"
  else
    note="token budget healthy"
  fi
  
  echo "$emoji Tokens (est): used ~$used/$token_capacity (~${max_pct}%), remaining ~$remaining — $note"
}

# =============================================================================
# PHASE 3: GUTTER DETECTION
# =============================================================================

# Time limit detection: if iteration runs >1 hour, trigger gutter
# Args: duration_seconds (iteration duration in seconds)
# Returns: 0 if gutter (exceeded limit), 1 if OK
# Note: Different from rotation - rotation continues, gutter stops
check_time_limit() {
  local duration_seconds="${1:-0}"
  local limit_seconds="${2:-3600}"  # Default 1 hour = 3600 seconds
  
  if [[ $duration_seconds -gt $limit_seconds ]]; then
    return 0  # Gutter detected
  else
    return 1  # OK
  fi
}

# Agent signal detection: grep agent output for <milhouse>GUTTER</milhouse>
# Args: output_file (path to agent output file, e.g., .milhouse/out.txt)
# Returns: 0 if gutter signal found, 1 if not found
check_agent_gutter_signal() {
  local output_file="${1:-}"
  
  if [[ -z "$output_file" ]] || [[ ! -f "$output_file" ]]; then
    return 1  # No output file, can't detect signal
  fi
  
  if grep -q '<milhouse>GUTTER</milhouse>' "$output_file" 2>/dev/null; then
    return 0  # Gutter signal found
  else
    return 1  # No signal found
  fi
}

# Git log error pattern detection: scan last 20 commits for repeated errors
# Args: workspace (optional, defaults to current directory)
#       commit_count (default 20)
#       error_threshold (default 3)
# Returns: 0 if gutter (repeated error), 1 if OK
# Detects if same error pattern appears 3+ times in recent commits
check_git_log_errors() {
  local workspace="${1:-.}"
  local commit_count="${2:-20}"  # Default: check last 20 commits
  local error_threshold="${3:-3}"  # Default: trigger if error appears 3+ times
  
  # macOS ships Bash 3.2 by default; avoid associative arrays (declare -A).
  if ! git -C "$workspace" rev-parse --git-dir > /dev/null 2>&1; then
    return 1
  fi
  
  # Look for repeated, normalized "error-like" commit messages.
  # We normalize by lowercasing and truncating to 50 chars, then count duplicates.
  if git -C "$workspace" log --oneline -n "$commit_count" 2>/dev/null \
    | sed 's/^[^ ]* //' \
    | grep -iE '(error|fail|failure|bug|broken|exception|crash)' \
    | tr '[:upper:]' '[:lower:]' \
    | cut -c 1-50 \
    | sort \
    | uniq -c \
    | awk -v threshold="$error_threshold" '{ if ($1 >= threshold) found=1 } END { exit (found ? 0 : 1) }'
  then
    return 0
  fi
  
  return 1
}

# Count files changed since a specific commit (best-effort).
# Args: workspace, base_commit
# Returns: number of files changed (0 if unknown/unavailable)
count_files_changed_since_commit() {
  local workspace="${1:-.}"
  local base_commit="${2:-}"
  
  if [[ -z "$base_commit" ]]; then
    echo "0"
    return 0
  fi
  
  if ! git -C "$workspace" rev-parse --git-dir > /dev/null 2>&1; then
    echo "0"
    return 0
  fi
  
  # If HEAD doesn't exist yet (fresh repo), treat as 0.
  if ! git -C "$workspace" rev-parse HEAD > /dev/null 2>&1; then
    echo "0"
    return 0
  fi
  
  git -C "$workspace" diff --name-only "$base_commit"..HEAD 2>/dev/null | wc -l | tr -d ' '
}

# Task file change detection: compare MILHOUSE_TASK.md hash between iterations
# Args: workspace (optional)
#       current_iteration
#       task_file (default MILHOUSE_TASK.md)
#       stale_threshold (default 2)
# Returns: 0 if gutter (no change for 2+ iterations), 1 if OK
# Stores task file hash in .milhouse/.task_hash.{iteration}
check_task_file_stale() {
  local workspace="${1:-.}"
  local current_iteration="${2:-0}"
  local task_file="${3:-MILHOUSE_TASK.md}"
  local stale_threshold="${4:-2}"  # Default: trigger if unchanged for 2+ iterations
  
  if [[ $current_iteration -lt $stale_threshold ]]; then
    # Need at least N iterations to check for staleness
    return 1  # OK (too early to tell)
  fi
  
  local task_file_path="$workspace/$task_file"
  if [[ ! -f "$task_file_path" ]]; then
    return 1  # No task file, can't check staleness
  fi
  
  # Calculate current hash
  local current_hash
  if command -v shasum &> /dev/null; then
    current_hash=$(shasum -a 256 "$task_file_path" 2>/dev/null | cut -d' ' -f1)
  elif command -v sha256sum &> /dev/null; then
    current_hash=$(sha256sum "$task_file_path" 2>/dev/null | cut -d' ' -f1)
  else
    # Fallback to md5 if available
    if command -v md5sum &> /dev/null; then
      current_hash=$(md5sum "$task_file_path" 2>/dev/null | cut -d' ' -f1)
    elif command -v md5 &> /dev/null; then
      current_hash=$(md5 -q "$task_file_path" 2>/dev/null)
    else
      return 1  # No hash utility available
    fi
  fi
  
  if [[ -z "$current_hash" ]]; then
    return 1  # Failed to calculate hash
  fi
  
  local milhouse_dir="$workspace/.milhouse"
  mkdir -p "$milhouse_dir"
  
  # Store current hash
  echo "$current_hash" > "$milhouse_dir/.task_hash.$current_iteration"
  
  # Check previous N iterations for same hash
  local unchanged_count=0
  local i=$((current_iteration - 1))
  local stop_at=$((current_iteration - stale_threshold))
  
  while [[ $i -ge $stop_at ]] && [[ $i -ge 0 ]]; do
    local prev_hash_file="$milhouse_dir/.task_hash.$i"
    if [[ -f "$prev_hash_file" ]]; then
      local prev_hash
      prev_hash=$(cat "$prev_hash_file" 2>/dev/null || echo "")
      if [[ "$prev_hash" == "$current_hash" ]]; then
        ((unchanged_count++)) || true
      else
        break  # Hash changed, no staleness
      fi
    fi
    ((i--)) || true
  done
  
  if [[ $unchanged_count -ge $stale_threshold ]]; then
    return 0  # Gutter detected: task file unchanged for threshold+ iterations
  else
    return 1  # OK: task file has changed
  fi
}

# Integrate all gutter detection checks: combine with OR logic
# Args: workspace
#       iteration_number
#       duration_seconds
#       output_file (optional)
#       task_file (optional, default MILHOUSE_TASK.md)
# Returns: 0 if gutter detected (with reason in stdout), 1 if OK
# Checks: git log errors, task file stale, time limit, agent signal
check_gutter() {
  local workspace="${1:-.}"
  local iteration_number="${2:-0}"
  local duration_seconds="${3:-0}"
  local output_file="${4:-}"
  local task_file="${5:-MILHOUSE_TASK.md}"
  
  local gutter_reason=""
  local gutter_detected=0
  
  # Check 1: Time limit (>1 hour)
  if check_time_limit "$duration_seconds"; then
    gutter_reason="iteration exceeded 1 hour limit"
    gutter_detected=1
  fi
  
  # Check 2: Agent gutter signal
  if [[ $gutter_detected -eq 0 ]] && [[ -n "$output_file" ]]; then
    if check_agent_gutter_signal "$output_file"; then
      gutter_reason="agent signaled gutter"
      gutter_detected=1
    fi
  fi
  
  # Check 3: Git log repeated errors
  if [[ $gutter_detected -eq 0 ]]; then
    if check_git_log_errors "$workspace"; then
      gutter_reason="repeated error pattern in git log"
      gutter_detected=1
    fi
  fi
  
  # Check 4: Task file stale (no progress)
  if [[ $gutter_detected -eq 0 ]] && [[ $iteration_number -gt 0 ]]; then
    if check_task_file_stale "$workspace" "$iteration_number" "$task_file"; then
      gutter_reason="task file unchanged for 2+ iterations"
      gutter_detected=1
    fi
  fi
  
  if [[ $gutter_detected -eq 1 ]]; then
    echo "$gutter_reason"
    return 0  # Gutter detected
  else
    return 1  # OK
  fi
}

# Log gutter reason in a clear format
# Args: gutter_reason (string from check_gutter())
log_gutter_reason() {
  local reason="${1:-}"
  
  if [[ -n "$reason" ]]; then
    show_warning "Gutter detected: $reason"
  fi
}

# =============================================================================
# PHASE 1: PREREQUISITE CHECKS
# =============================================================================

# Check that all prerequisites are met
# Args: workspace
# Returns: 0 if all good, 1 if any missing
check_prerequisites() {
  local workspace="$1"
  local require_task_file="${2:-1}"
  local errors=0
  
  # Check git repository
  if ! git -C "$workspace" rev-parse --git-dir > /dev/null 2>&1; then
    show_error "Not a git repository" \
      "Location: $workspace

Milhouse requires a git repository for state tracking.

Fix: Run the following command in your project:
  cd \"$workspace\" && git init"
    errors=$((errors + 1))
  fi
  
  # Check cursor-agent
  if ! command -v cursor-agent > /dev/null 2>&1; then
    show_error "cursor-agent CLI not found" \
      "Milhouse requires cursor-agent to run AI iterations.

Fix: Install cursor-agent and ensure it's in your PATH.
  1. Install: npm install -g cursor-agent
  2. Verify: cursor-agent --version"
    errors=$((errors + 1))
  fi
  
  # Check task file
  if [[ "$require_task_file" == "1" ]] && [[ ! -f "$workspace/MILHOUSE_TASK.md" ]]; then
    show_error "Task file not found" \
      "Expected: $workspace/MILHOUSE_TASK.md

Milhouse needs a task file with completion criteria to work on.

Fix: Create MILHOUSE_TASK.md with:
  - A description of what you want built
  - Completion criteria as checkboxes: - [ ] Criterion 1

Example:
  # My Task
  ## Completion criteria
  - [ ] Create database schema
  - [ ] Implement API endpoints"
    errors=$((errors + 1))
  fi
  
  if [[ $errors -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}

# =============================================================================
# PHASE 1: PROMPT TEMPLATE
# =============================================================================

# Build the prompt for the agent
# Args: workspace, iteration
# Returns: prompt string via echo
build_prompt() {
  local workspace="$1"
  local iteration="$2"
  
  cat << EOF
# Milhouse Iteration $iteration

You are an autonomous development agent using the Milhouse methodology.

## FIRST: Read State Files

Before doing anything:
1. Read \`MILHOUSE_TASK.md\` - your task and completion criteria
2. Read \`.milhouse/guardrails.md\` - lessons from past failures (FOLLOW THESE)
3. Read \`.milhouse/progress.md\` - what's been accomplished

## Working Directory (Critical)

You are already in a git repository. Work HERE, not in a subdirectory:

- Do NOT run \`git init\` - the repo already exists
- Do NOT run scaffolding commands that create nested directories (\`npx create-*\`, \`npm init\`, etc.)
- If you need to scaffold, use flags like \`--no-git\` or scaffold into the current directory (\`.\`)
- All code should live at the repo root or in subdirectories you create manually

## Git Protocol (Critical)

Milhouse's strength is state-in-git, not LLM memory. Commit early and often:

1. After completing each criterion, commit your changes:
   \`git add -A && git commit -m 'milhouse: implement state tracker'\`
   \`git add -A && git commit -m 'milhouse: fix async race condition'\`
   \`git add -A && git commit -m 'milhouse: add CLI adapter with commander'\`
   Always describe what you actually did - never use placeholders like '<description>'
2. After any significant code change (even partial): commit with descriptive message
3. Before any risky refactor: commit current state as checkpoint
4. Push after every 2-3 commits: \`git push\`

If you get rotated, the next agent picks up from your last commit. Your commits ARE your memory.

## Task Execution

1. Work on the next unchecked criterion in MILHOUSE_TASK.md (look for \`[ ]\`)
2. Run tests after changes if applicable
3. **Mark completed criteria**: Edit MILHOUSE_TASK.md and change \`[ ]\` to \`[x]\`
   - Example: \`- [ ] Implement parser\` becomes \`- [x] Implement parser\`
   - This is how progress is tracked - YOU MUST update the file
4. Update \`.milhouse/progress.md\` with what you accomplished
5. When ALL criteria show \`[x]\`: output \`<milhouse>COMPLETE</milhouse>\`
6. If stuck 3+ times on same issue: output \`<milhouse>GUTTER</milhouse>\`

## Guardrails

ALWAYS read \`.milhouse/guardrails.md\` first. These are lessons learned from past failures. Follow them strictly to avoid repeating mistakes.

## Completion

When you've checked all boxes in MILHOUSE_TASK.md:
- Output \`<milhouse>COMPLETE</milhouse>\`
- Make a final commit
- The loop will stop

If you're truly stuck and making no progress:
- Output \`<milhouse>GUTTER</milhouse>\`
- The loop will stop for human review

Work in: $workspace

EOF
}

# =============================================================================
# PHASE 1: CURSOR-AGENT EXECUTION
# =============================================================================

# Run a single agent iteration
# Args: workspace, iteration, model
# Returns: exit code and captures output
run_agent_iteration() {
  local workspace="$1"
  local iteration="$2"
  local model="${3:-$MODEL}"
  local output_file="$workspace/.milhouse/out.txt"
  local raw_stream_file="$workspace/.milhouse/out.stream.jsonl"
  
  # Build prompt
  local prompt
  prompt=$(build_prompt "$workspace" "$iteration")
  
  # Change to workspace
  cd "$workspace" || return 1
  mkdir -p "$workspace/.milhouse"
  init_out_log "$workspace"
  
  show_info "Running iteration $iteration..."
  show_info "Model: $model"
  show_info "Output: $output_file"
  echo ""
  
  # Write a header immediately so “tail -f” shows something right away.
  log_out_section "$workspace" "Iteration $iteration — starting"
  log_out "$workspace" "Mode: agent-run"
  log_out "$workspace" "Model: $model"
  log_out "$workspace" "Prompt length: ${#prompt} chars"
  log_out "$workspace" "Milhouse will append cleaned agent output below."
  log_out "$workspace" "Raw agent stream: $raw_stream_file"
  
  # Execute the agent.
  #
  # Note: we intentionally avoid wrapping cursor-agent with `gum spin` here.
  # In practice, spinner wrappers can cause “Aborting operation...” or apparent hangs.
  # The “Follow along” tail command is the preferred live view.
  echo "Agent working on iteration $iteration..."
  {
    cursor-agent -p --force \
      --output-format stream-json \
      --stream-partial-output \
      --workspace "$workspace" \
      --model "$model" \
      "$prompt" 2>&1 \
      | tee -a "$raw_stream_file" \
      | clean_cursor_agent_stream >> "$output_file"
  }
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    show_success "Iteration $iteration completed"
    log_out "$workspace" "Agent exit: 0 (success)"
  else
    show_warning "Iteration $iteration exited with code $exit_code"
    show_info "Check $output_file for details. The loop will continue."
    log_out "$workspace" "Agent exit: $exit_code (non-zero)"
  fi
  
  return $exit_code
}

# =============================================================================
# PHASE 1: SINGLE ITERATION MODE
# =============================================================================

# Run a single iteration (for --once mode)
# Args: workspace, model
# Returns: 0 if complete, 1 if incomplete
run_single_iteration() {
  local workspace="$1"
  local model="${2:-$MODEL}"
  local output_file="$workspace/.milhouse/out.txt"
  
  init_out_log "$workspace"
  log_out_section "$workspace" "Single iteration (mode: --once)"
  log_out "$workspace" "Model: $model"
  
  show_header "📋 Single Iteration Mode" 12
  echo ""
  
  # Check current completion status
  local task_status
  task_status=$(check_task_complete "$workspace")
  
  if [[ "$task_status" == "COMPLETE" ]]; then
    echo "🎉 Task already complete! All criteria are checked."
    log_out "$workspace" "Status: COMPLETE (no work needed)"
    return 0
  fi
  
  # Show current progress
  local counts
  counts=$(read_task_file "$workspace")
  IFS=':' read -r total done_count remaining <<< "$counts"
  local iteration
  iteration=$(get_iteration "$workspace")
  
  show_progress "$((iteration + 1))" "$done_count" "$total" "$remaining"
  echo ""
  log_out "$workspace" "Progress at start: $done_count/$total ($remaining remaining)"
  
  # Commit any uncommitted work first
  cd "$workspace" || return 1
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "📦 Committing uncommitted changes..."
    log_out "$workspace" "Checkpoint: committing uncommitted changes before run"
    git add -A
    git commit -m "milhouse: checkpoint before single iteration" || true
    echo ""
  fi
  
  # Run the iteration
  local iteration
  iteration=$(increment_iteration "$workspace")
  
  local start_time
  start_time=$(track_iteration_start)
  local commits_start
  commits_start=$(track_commits_start "$workspace")
  local head_start=""
  head_start=$(git -C "$workspace" rev-parse HEAD 2>/dev/null || echo "")
  
  echo "Follow along:"
  echo "  tail -f $output_file"
  echo ""
  log_out "$workspace" "Follow along: tail -f $output_file"
  
  run_agent_iteration "$workspace" "$iteration" "$model"
  local exit_code=$?
  
  # Keep TODO.md in sync with completed MILHOUSE_TASK.md items
  sync_task_progress_to_todo "$workspace"
  log_out "$workspace" "Synced MILHOUSE_TASK.md → TODO.md (best-effort)"
  
  local duration_seconds
  duration_seconds=$(calculate_iteration_duration "$start_time")
  local commits_in_iteration
  commits_in_iteration=$(count_commits_in_iteration "$commits_start" "$workspace")
  local files_changed
  files_changed=$(count_files_changed_since_commit "$workspace" "$head_start")
  log_out "$workspace" "Iteration stats: duration=${duration_seconds}s commits=${commits_in_iteration} files=${files_changed}"
  
  local health
  health=$(get_context_health_emoji "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL")
  local token_line
  token_line=$(get_token_budget_status_line "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL")
  show_info "Context health: $health"
  log_out "$workspace" "$token_line"
  
  # Rotation reporting (Phase 2): tell the operator why we'd rotate.
  local rotation_reason=""
  if rotation_reason=$(should_rotate "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL"); then
    log_rotation_reason "$rotation_reason"
    log_out "$workspace" "$health Token reset will occur soon — rotation triggered: $rotation_reason"
  fi
  
  # Gutter detection (Phase 3): stop and report why.
  local gutter_reason=""
  if gutter_reason=$(check_gutter "$workspace" "$iteration" "$duration_seconds" "$output_file" "MILHOUSE_TASK.md"); then
    log_gutter_reason "$gutter_reason"
    log_out "$workspace" "Gutter detected: $gutter_reason"
    echo ""
    echo "Stopped: $gutter_reason"
    return 1
  fi
  
  # Check completion after iteration
  task_status=$(check_task_complete "$workspace")
  counts=$(read_task_file "$workspace")
  IFS=':' read -r total done_count remaining <<< "$counts"
  
  echo ""
  show_header "📋 Single Iteration Complete" 12
  echo ""
  
  if [[ "$task_status" == "COMPLETE" ]]; then
    show_success "Task completed in single iteration!"
    echo ""
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    log_out "$workspace" "Status: COMPLETE"
    return 0
  else
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    echo ""
    show_info "Review the changes and run again or proceed to full loop."
    log_out "$workspace" "Status: INCOMPLETE ($remaining remaining)"
    return 1
  fi
}

# =============================================================================
# PHASE 1: MAIN LOOP
# =============================================================================

# Run the main loop until completion or max iterations
# Args: workspace, max_iterations, model
# Returns: 0 if complete, 1 if max iterations reached
run_milhouse_loop() {
  local workspace="$1"
  local max_iterations="${2:-$MAX_ITERATIONS}"
  local model="${3:-$MODEL}"
  local output_file="$workspace/.milhouse/out.txt"
  
  init_out_log "$workspace"
  log_out_section "$workspace" "Loop run (mode: --loop)"
  log_out "$workspace" "Model: $model"
  log_out "$workspace" "Max iterations: $max_iterations"
  
  show_header "🔄 Loop Mode (max: $max_iterations iterations)" 12
  echo ""
  
  # Commit any uncommitted work first
  cd "$workspace" || return 1
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "📦 Committing uncommitted changes..."
    log_out "$workspace" "Checkpoint: committing uncommitted changes before loop"
    git add -A
    git commit -m "milhouse: initial commit before loop" || true
    echo ""
  fi
  
  # Get starting iteration
  local iteration
  iteration=$(get_iteration "$workspace")
  
  # Check if already complete
  local task_status
  task_status=$(check_task_complete "$workspace")
  if [[ "$task_status" == "COMPLETE" ]]; then
    echo "🎉 Task already complete! All criteria are checked."
    return 0
  fi
  
  echo "🚀 Starting Milhouse loop..."
  echo ""
  echo "Follow along:"
  echo "  tail -f $output_file"
  echo ""
  log_out "$workspace" "Follow along: tail -f $output_file"
  
  # Main loop
  while [[ $iteration -lt $max_iterations ]]; do
    # Increment iteration
    iteration=$(increment_iteration "$workspace")
    
    # Show progress at start of iteration
    local counts
    counts=$(read_task_file "$workspace")
    IFS=':' read -r total done_count remaining <<< "$counts"
    
    show_section "Iteration $iteration / $max_iterations"
    echo ""
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    echo ""
    log_out_section "$workspace" "Iteration $iteration"
    log_out "$workspace" "Progress: $done_count/$total ($remaining remaining)"
    
    local start_time
    start_time=$(track_iteration_start)
    local commits_start
    commits_start=$(track_commits_start "$workspace")
    local head_start=""
    head_start=$(git -C "$workspace" rev-parse HEAD 2>/dev/null || echo "")
    
    # Run iteration
    run_agent_iteration "$workspace" "$iteration" "$model"
    local exit_code=$?
    
    # Keep TODO.md in sync with completed MILHOUSE_TASK.md items
    sync_task_progress_to_todo "$workspace"
    log_out "$workspace" "Synced MILHOUSE_TASK.md → TODO.md (best-effort)"
    
    local duration_seconds
    duration_seconds=$(calculate_iteration_duration "$start_time")
    local commits_in_iteration
    commits_in_iteration=$(count_commits_in_iteration "$commits_start" "$workspace")
    local files_changed
    files_changed=$(count_files_changed_since_commit "$workspace" "$head_start")
    log_out "$workspace" "Iteration stats: duration=${duration_seconds}s commits=${commits_in_iteration} files=${files_changed}"
    
    local health
    health=$(get_context_health_emoji "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL")
    local token_line
    token_line=$(get_token_budget_status_line "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL")
    show_info "Context health: $health"
    log_out "$workspace" "$token_line"
    
    # Check completion
    task_status=$(check_task_complete "$workspace")
    
    if [[ "$task_status" == "COMPLETE" ]]; then
      echo ""
      show_header "🎉 MILHOUSE COMPLETE! All criteria satisfied." 10
      echo ""
      show_success "Completed in $iteration iteration(s)."
      show_info "Check git log for detailed history."
      log_out "$workspace" "Status: COMPLETE"
      return 0
    fi
    
    # Rotation reporting (Phase 2): tell the operator why we'd rotate.
    local rotation_reason=""
    if rotation_reason=$(should_rotate "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL"); then
      log_rotation_reason "$rotation_reason"
      echo ""
      log_out "$workspace" "$health Token reset will occur soon — rotation triggered: $rotation_reason"
    fi
    
    # Gutter detection (Phase 3): stop and report why.
    local gutter_reason=""
    if gutter_reason=$(check_gutter "$workspace" "$iteration" "$duration_seconds" "$output_file" "MILHOUSE_TASK.md"); then
      echo ""
      show_header "🚨 Gutter detected - stopping loop" 1
      echo ""
      show_warning "Reason: $gutter_reason"
      echo ""
      show_info "Review $output_file and consider:"
      echo "  1. Add a guardrail to .milhouse/guardrails.md"
      echo "  2. Simplify MILHOUSE_TASK.md"
      echo "  3. Fix the blocking issue manually"
      echo ""
      log_out "$workspace" "Gutter detected: $gutter_reason"
      return 1
    fi
    
    # Brief pause between iterations
    sleep 2
    
    echo ""
  done
  
  # Max iterations reached
  echo ""
  show_header "⚠️  Maximum iterations reached ($max_iterations)" 3
  echo ""
  log_out "$workspace" "Status: STOPPED (max iterations reached: $max_iterations)"
  task_status=$(check_task_complete "$workspace")
  if [[ "$task_status" == "COMPLETE" ]]; then
    show_success "Task is complete!"
    log_out "$workspace" "Final status: COMPLETE"
    return 0
  else
    local counts
    counts=$(read_task_file "$workspace")
    IFS=':' read -r total done_count remaining <<< "$counts"
    show_progress "$max_iterations" "$done_count" "$total" "$remaining"
    echo ""
    show_info "Review progress and continue or adjust task."
    log_out "$workspace" "Final status: INCOMPLETE ($remaining remaining)"
    return 1
  fi
}

# =============================================================================
# PHASE 4: INTERACTIVE SETUP
# =============================================================================

# Available models for selection
AVAILABLE_MODELS=(
  "opus-4.5-thinking"
  "opus-4"
  "sonnet-4"
  "sonnet-3.5"
)

# Interactive model selection
# Returns: selected model via echo
select_model_gum() {
  local selected
  selected=$(gum choose --header "Select AI model:" "${AVAILABLE_MODELS[@]}")
  echo "$selected"
}

select_model_plain() {
  echo "Select AI model:" >&2
  local i=1
  for model in "${AVAILABLE_MODELS[@]}"; do
    echo "  $i) $model" >&2
    ((i++))
  done
  read -rp "Choice [1-${#AVAILABLE_MODELS[@]}] (default: 1): " choice
  choice="${choice:-1}"
  # Validate and return
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#AVAILABLE_MODELS[@]}" ]]; then
    echo "${AVAILABLE_MODELS[$((choice - 1))]}"
  else
    echo "${AVAILABLE_MODELS[0]}"
  fi
}

# Interactive max iterations input
# Returns: max iterations via echo
select_iterations_gum() {
  local selected
  selected=$(gum input --placeholder "20" --value "20" --header "Max iterations:")
  echo "${selected:-20}"
}

select_iterations_plain() {
  read -rp "Max iterations [default: 20]: " iterations
  echo "${iterations:-20}"
}

# Interactive confirmation
# Returns: 0 if confirmed, 1 if cancelled
confirm_setup_gum() {
  local model="$1"
  local iterations="$2"
  local workspace="$3"
  
  echo ""
  gum style --border double --padding "0 2" --border-foreground 212 \
    "Configuration Summary" \
    "" \
    "Model:      $model" \
    "Max iter:   $iterations" \
    "Workspace:  $workspace"
  echo ""
  
  gum confirm "Start Milhouse with these settings?"
}

confirm_setup_plain() {
  local model="$1"
  local iterations="$2"
  local workspace="$3"
  
  echo ""
  show_header "Configuration Summary" 212
  echo ""
  show_info "Model:      $model"
  show_info "Max iter:   $iterations"
  show_info "Workspace:  $workspace"
  echo ""
  read -rp "Start Milhouse with these settings? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy] ]]
}

# Main interactive setup function
# Sets MODEL, MAX_ITERATIONS based on user input
# Returns: 0 if setup complete, 1 if cancelled
interactive_setup() {
  local workspace="$1"
  
  echo ""
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --border rounded --padding "0 2" --border-foreground 12 \
      "Milhouse Interactive Setup"
    echo ""
    
    # Model selection
    MODEL=$(select_model_gum)
    
    # Max iterations
    MAX_ITERATIONS=$(select_iterations_gum)
    
    # Confirm
    if ! confirm_setup_gum "$MODEL" "$MAX_ITERATIONS" "$workspace"; then
      gum style --foreground 3 "Setup cancelled."
      return 1
    fi
  else
    show_header "Milhouse Interactive Setup" 12
    echo ""
    show_info "(Install 'gum' for a better experience: https://github.com/charmbracelet/gum)"
    echo ""
    
    # Model selection
    MODEL=$(select_model_plain)
    
    # Max iterations
    MAX_ITERATIONS=$(select_iterations_plain)
    
    # Confirm
    if ! confirm_setup_plain "$MODEL" "$MAX_ITERATIONS" "$workspace"; then
      echo "Setup cancelled."
      return 1
    fi
  fi
  
  echo ""
  echo "Starting Milhouse..."
  echo ""
  return 0
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
  show_header "Milhouse: Simplified Autonomous Development Loop" 212
  echo ""
  show_info "Mode:      $MODE"
  show_info "Workspace: $WORKSPACE"
  echo ""
  
  # Check prerequisites first
  # Allow missing MILHOUSE_TASK.md: we can create it interactively.
  if ! check_prerequisites "$WORKSPACE" 0; then
    echo ""
    show_info "Fix the errors above and try again."
    exit 1
  fi
  
  # Initialize state directory
  init_state "$WORKSPACE"
  
  # If task file is missing, ask what to work on (TODO.md picker or custom goal).
  if ! ensure_task_file "$WORKSPACE"; then
    show_warning "No task selected. Exiting."
    exit 0
  fi
  
  # Execute based on mode
  case "$MODE" in
    once)
      run_single_iteration "$WORKSPACE" "$MODEL"
      exit $?
      ;;
    loop)
      run_milhouse_loop "$WORKSPACE" "$MAX_ITERATIONS" "$MODEL"
      exit $?
      ;;
    setup)
      if interactive_setup "$WORKSPACE"; then
        # After setup, run the loop with configured settings
        run_milhouse_loop "$WORKSPACE" "$MAX_ITERATIONS" "$MODEL"
        exit $?
      else
        exit 0
      fi
      ;;
    *)
      show_error "Unknown mode: $MODE" \
        "This mode is not recognized.

Valid modes:
  --once   Run a single iteration then stop
  --loop   Run continuous loop until completion
  --setup  Interactive setup

Fix: Use a valid mode flag:
  $0 --loop
  $0 --once
  $0 --setup"
      exit 1
      ;;
  esac
}

# Run main function
main
