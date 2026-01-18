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
    gum style --border single --padding "0 1" --border-foreground 8 "$progress_text"
  else
    echo "┌──────────────────────────────────────────────────────────────────┐"
    printf "│ %-66s │\n" "$progress_text"
    echo "└──────────────────────────────────────────────────────────────────┘"
  fi
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
  if [[ ! -f "$workspace/MILHOUSE_TASK.md" ]]; then
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
  
  # Build prompt
  local prompt
  prompt=$(build_prompt "$workspace" "$iteration")
  
  # Change to workspace
  cd "$workspace" || return 1
  
  echo "🚀 Running iteration $iteration..." >&2
  echo "   Model: $model" >&2
  echo "   Output: $output_file" >&2
  echo "" >&2
  
  # Execute and capture output (prompt passed as a single argument)
  cursor-agent -p --force --model "$model" "$prompt" > "$output_file" 2>&1
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    show_success "Iteration $iteration completed"
  else
    show_warning "Iteration $iteration exited with code $exit_code"
    show_info "Check $output_file for details. The loop will continue."
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
  
  echo "═══════════════════════════════════════════════════════════════════"
  echo "📋 Single Iteration Mode"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  
  # Check current completion status
  local task_status
  task_status=$(check_task_complete "$workspace")
  
  if [[ "$task_status" == "COMPLETE" ]]; then
    echo "🎉 Task already complete! All criteria are checked."
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
  
  # Commit any uncommitted work first
  cd "$workspace" || return 1
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "📦 Committing uncommitted changes..."
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
  
  run_agent_iteration "$workspace" "$iteration" "$model"
  local exit_code=$?
  
  local duration_seconds
  duration_seconds=$(calculate_iteration_duration "$start_time")
  local commits_in_iteration
  commits_in_iteration=$(count_commits_in_iteration "$commits_start" "$workspace")
  local files_changed
  files_changed=$(count_files_changed_since_commit "$workspace" "$head_start")
  
  # Rotation reporting (Phase 2): tell the operator why we'd rotate.
  local rotation_reason=""
  if rotation_reason=$(should_rotate "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL"); then
    log_rotation_reason "$rotation_reason"
  fi
  
  # Gutter detection (Phase 3): stop and report why.
  local gutter_reason=""
  if gutter_reason=$(check_gutter "$workspace" "$iteration" "$duration_seconds" "$output_file" "MILHOUSE_TASK.md"); then
    log_gutter_reason "$gutter_reason"
    echo ""
    echo "Stopped: $gutter_reason"
    return 1
  fi
  
  # Check completion after iteration
  task_status=$(check_task_complete "$workspace")
  counts=$(read_task_file "$workspace")
  IFS=':' read -r total done_count remaining <<< "$counts"
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "📋 Single Iteration Complete"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  
  if [[ "$task_status" == "COMPLETE" ]]; then
    show_success "Task completed in single iteration!"
    echo ""
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    return 0
  else
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    echo ""
    show_info "Review the changes and run again or proceed to full loop."
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
  
  echo "═══════════════════════════════════════════════════════════════════"
  echo "🔄 Loop Mode (max: $max_iterations iterations)"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  
  # Commit any uncommitted work first
  cd "$workspace" || return 1
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "📦 Committing uncommitted changes..."
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
  
  # Main loop
  while [[ $iteration -lt $max_iterations ]]; do
    # Increment iteration
    iteration=$(increment_iteration "$workspace")
    
    # Show progress at start of iteration
    local counts
    counts=$(read_task_file "$workspace")
    IFS=':' read -r total done_count remaining <<< "$counts"
    
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Iteration $iteration / $max_iterations"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    show_progress "$iteration" "$done_count" "$total" "$remaining"
    echo ""
    
    local start_time
    start_time=$(track_iteration_start)
    local commits_start
    commits_start=$(track_commits_start "$workspace")
    local head_start=""
    head_start=$(git -C "$workspace" rev-parse HEAD 2>/dev/null || echo "")
    
    # Run iteration
    run_agent_iteration "$workspace" "$iteration" "$model"
    local exit_code=$?
    
    local duration_seconds
    duration_seconds=$(calculate_iteration_duration "$start_time")
    local commits_in_iteration
    commits_in_iteration=$(count_commits_in_iteration "$commits_start" "$workspace")
    local files_changed
    files_changed=$(count_files_changed_since_commit "$workspace" "$head_start")
    
    # Check completion
    task_status=$(check_task_complete "$workspace")
    
    if [[ "$task_status" == "COMPLETE" ]]; then
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      echo "🎉 MILHOUSE COMPLETE! All criteria satisfied."
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""
      echo "Completed in $iteration iteration(s)."
      echo "Check git log for detailed history."
      return 0
    fi
    
    # Rotation reporting (Phase 2): tell the operator why we'd rotate.
    local rotation_reason=""
    if rotation_reason=$(should_rotate "$duration_seconds" "$files_changed" "$commits_in_iteration" "$iteration" "$ROTATION_INTERVAL"); then
      log_rotation_reason "$rotation_reason"
      echo ""
    fi
    
    # Gutter detection (Phase 3): stop and report why.
    local gutter_reason=""
    if gutter_reason=$(check_gutter "$workspace" "$iteration" "$duration_seconds" "$output_file" "MILHOUSE_TASK.md"); then
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      echo "🚨 Gutter detected - stopping loop"
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""
      echo "Reason: $gutter_reason"
      echo ""
      echo "Review $output_file and consider:"
      echo "  1. Add a guardrail to .milhouse/guardrails.md"
      echo "  2. Simplify MILHOUSE_TASK.md"
      echo "  3. Fix the blocking issue manually"
      echo ""
      log_gutter_reason "$gutter_reason"
      return 1
    fi
    
    # Brief pause between iterations
    sleep 2
    
    echo ""
  done
  
  # Max iterations reached
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "⚠️  Maximum iterations reached ($max_iterations)"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  task_status=$(check_task_complete "$workspace")
  if [[ "$task_status" == "COMPLETE" ]]; then
    show_success "Task is complete!"
    return 0
  else
    local counts
    counts=$(read_task_file "$workspace")
    IFS=':' read -r total done_count remaining <<< "$counts"
    show_progress "$max_iterations" "$done_count" "$total" "$remaining"
    echo ""
    show_info "Review progress and continue or adjust task."
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
  echo "═══════════════════════════════════════════════════════════════════"
  echo "Configuration Summary"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Model:      $model"
  echo "  Max iter:   $iterations"
  echo "  Workspace:  $workspace"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
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
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Milhouse Interactive Setup"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "(Install 'gum' for a better experience: https://github.com/charmbracelet/gum)"
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
  echo "Milhouse: Simplified Autonomous Development Loop"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "Mode:     $MODE"
  echo "Workspace: $WORKSPACE"
  echo ""
  
  # Check prerequisites first
  if ! check_prerequisites "$WORKSPACE"; then
    echo ""
    show_info "Fix the errors above and try again."
    exit 1
  fi
  
  # Initialize state directory
  init_state "$WORKSPACE"
  
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
