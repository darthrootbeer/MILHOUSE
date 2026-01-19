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

# --- Task announcements (MILHOUSE_TASK.md) -----------------------------------

trim_one_line() {
  local s="$1"
  # Collapse whitespace + trim.
  s="$(printf "%s" "$s" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//')"
  printf "%s" "$s"
}

# Return first unchecked checkbox line (without "- [ ]") as a single line.
get_first_unchecked_task_one_liner() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  [[ -f "$task_file" ]] || { echo ""; return 1; }
  local line
  line="$(grep -E '^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+' "$task_file" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return 1
  fi
  line="$(printf "%s" "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+//')"
  trim_one_line "$line"
}

# List IDs for a given state in MILHOUSE_TASK.md ("x" or " ").
list_task_ids_by_state() {
  local workspace="$1"
  local state="$2" # "x" or " "
  local task_file="$workspace/MILHOUSE_TASK.md"
  [[ -f "$task_file" ]] || { echo ""; return 0; }
  if [[ "$state" == "x" ]]; then
    grep -E '^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+\[[A-Za-z0-9]+\]' "$task_file" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+\[([A-Za-z0-9]+)\].*$/\1/' \
      | sort -u || true
  else
    grep -E '^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+\[[A-Za-z0-9]+\]' "$task_file" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+\[([A-Za-z0-9]+)\].*$/\1/' \
      | sort -u || true
  fi
}

get_task_one_liner_for_id() {
  local workspace="$1"
  local id="$2"
  local task_file="$workspace/MILHOUSE_TASK.md"
  [[ -f "$task_file" ]] || { echo ""; return 1; }
  local line
  line="$(grep -E "^[[:space:]]*[-*][[:space:]]+\\[(x| )\\][[:space:]]+\\[${id}\\]" "$task_file" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return 1
  fi
  line="$(printf "%s" "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[(x| )\][[:space:]]+//')"
  trim_one_line "$line"
}

show_task_start() {
  local workspace="$1"
  local one
  one="$(get_first_unchecked_task_one_liner "$workspace" || true)"
  if [[ -z "$one" ]]; then
    return 0
  fi
  show_info "Working on: $one"
  log_out "$workspace" "Working on: $one"
}

show_task_completed() {
  local workspace="$1"
  local one="$2"
  if [[ -z "$one" ]]; then
    return 0
  fi
  if [[ "$HAS_GUM" == "true" ]]; then
    gum style --foreground 10 --bold "✅ Completed: $one"
  else
    echo -e "\033[32m✅ Completed: $one\033[0m"
  fi
  log_out "$workspace" "✅ Completed: $one"
}

# Build a short, readable menu label for a TODO line.
# Output format: "<first ~64 chars of description> [ABC123]"
todo_menu_label_for_line() {
  local line="$1"
  local id=""
  id="$(echo "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+\[([A-Za-z0-9]+)\].*$/\1/' 2>/dev/null || true)"
  if [[ -z "$id" ]] || [[ "$id" == "$line" ]]; then
    id=""
  fi

  local desc
  desc="$(echo "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]+//; s/^[[:space:]]*\[[A-Za-z0-9]+\]\([^)]*\)[[:space:]]*-[[:space:]]*//' 2>/dev/null || true)"
  if [[ -z "$desc" ]]; then
    desc="$line"
  fi

  # Truncate for quick scanning.
  local max=64
  local short="$desc"
  if [[ ${#short} -gt $max ]]; then
    short="$(printf "%.${max}s" "$short")…"
  fi

  if [[ -n "$id" ]]; then
    echo "$short [$id]"
  else
    echo "$short"
  fi
}

# Given a list of TODO lines and selected menu labels, return original TODO lines (newline-separated).
todo_lines_from_selected_labels() {
  local all_lines="$1"
  local selected_labels="$2"
  local out=""

  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    local id
    id="$(echo "$label" | sed -E 's/.*\[([A-Za-z0-9]+)\][[:space:]]*$/\1/' 2>/dev/null || true)"
    if [[ -z "$id" ]] || [[ "$id" == "$label" ]]; then
      continue
    fi
    local match
    match="$(printf "%s\n" "$all_lines" | grep -E "^[[:space:]]*[-*][[:space:]]+\\[ \\][[:space:]]+\\[${id}\\]" | head -n 1 || true)"
    if [[ -n "$match" ]]; then
      out="${out}${match}"$'\n'
    fi
  done <<< "$selected_labels"

  printf "%s" "$out"
}

# Pick TODO items (interactive) and write MILHOUSE_TASK.md.
pick_tasks_from_todo_md() {
  local workspace="$1"
  local items
  items="$(list_unchecked_todo_items "$workspace")"
  if [[ -z "$items" ]]; then
    show_error "No unchecked TODO items found" \
      "Milhouse looked for unchecked items in:
  $workspace/TODO.md

Fix: Add tasks in TODO.md using this format:
  - [ ] [ABC123](TODO/ABC123.md) - My next task"
    return 1
  fi

  local selected=""
  if [[ "$HAS_GUM" == "true" ]]; then
    local menu
    menu="$(while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      todo_menu_label_for_line "$line"
    done <<< "$items")"
    local picked=""
    local attempts=0
    while true; do
      attempts=$((attempts + 1))
      picked="$(printf "%s\n" "$menu" | gum choose --no-limit --header "Select TODO items (space to select, enter to submit):")" || picked=""
      selected="$(todo_lines_from_selected_labels "$items" "$picked")"

      if [[ -n "$selected" ]]; then
        break
      fi

      # If user pressed Enter without selecting (common), retry once with a clearer hint.
      show_warning "No TODO items selected. Tip: press Space to select, then Enter to submit."
      if [[ $attempts -ge 2 ]]; then
        return 1
      fi
    done
  else
    show_info "Paste the TODO lines you want Milhouse to work on (end with an empty line):"
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && break
      selected="${selected}${line}"$'\n'
    done
  fi

  create_task_from_todo_selection "$workspace" "$selected"
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
  
  reset_iteration_for_new_task_run "$workspace"
  local first
  first="$(get_first_unchecked_task_one_liner "$workspace" || true)"
  if [[ -n "$first" ]]; then
    show_info "Selected: $first"
    log_out "$workspace" "Selected: $first"
  fi
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
    local status
    status="$(check_task_complete "$workspace" || true)"

    # If the task file is runnable and still has work, keep going.
    if [[ "$status" == INCOMPLETE:* ]]; then
      return 0
    fi

    # If the task file is complete but TODO.md still has unchecked items, prompt for a new run.
    if [[ "$status" == "COMPLETE" ]]; then
      local items
      items="$(list_unchecked_todo_items "$workspace")"
      if [[ -n "$items" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
        show_warning "MILHOUSE_TASK.md is complete, but TODO.md still has unchecked items."
        show_info "Pick tasks from TODO.md to start a new run."
        pick_tasks_from_todo_md "$workspace"
        return $?
      fi
      return 0
    fi

    # If task file exists but has no checkbox criteria, treat it as “missing” and go to setup below.
    if [[ "$status" == "NO_CRITERIA" ]]; then
      show_warning "MILHOUSE_TASK.md has no checkbox criteria. Please pick tasks or define a goal."
    fi
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
    pick_tasks_from_todo_md "$workspace"
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
  
  reset_iteration_for_new_task_run "$workspace"
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
      echo "Tip: set MILHOUSE_AGENT_OUTPUT_MODE=stream-json to also save raw stream to: .milhouse/out.stream.jsonl"
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

def looks_like_json(s: str) -> bool:
  s = (s or "").lstrip()
  return s.startswith("{") or s.startswith("[")

def summarize_tool_use(item: dict) -> str:
  name = item.get("name") or item.get("tool_name") or item.get("tool") or "tool"
  inp = item.get("input") or item.get("arguments") or {}
  if not isinstance(inp, dict):
    return f"🛠️ {name}"
  path = inp.get("path") or inp.get("file_path") or inp.get("target") or inp.get("downloadPath")
  if isinstance(path, str) and path.strip():
    return f"🛠️ {name} → {path}"
  return f"🛠️ {name}"

for line in sys.stdin:
  raw = line.rstrip("\n")
  if not raw.strip():
    continue
  try:
    obj = json.loads(raw)
  except Exception:
    # Keep only genuinely useful non-JSON lines.
    # Drop giant JSON-ish blobs that failed to parse (they are unreadable in tail -f).
    if looks_like_json(raw):
      continue
    # Prefer to keep obvious error lines.
    low = raw.lower()
    if ("error" in low) or ("traceback" in low) or ("exception" in low):
      emit(raw)
    continue

  t = obj.get("type")
  if t != "assistant":
    continue

  msg = obj.get("message") or {}
  content = msg.get("content") or []

  # Summarize tool calls in one clean line (instead of dumping JSON).
  for c in content:
    if isinstance(c, dict) and c.get("type") in ("tool_use", "tool_call"):
      emit(summarize_tool_use(c))

  # Heuristic: only print the "final" assistant message, not partial fragments.
  # The partial fragments tend to be tiny; the final tends to include model_call_id.
  if not obj.get("model_call_id"):
    continue

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
# OUT.TXT HEARTBEAT (periodic, readable progress)
# =============================================================================

estimate_tokens_from_chars() {
  local chars="${1:-0}"
  if [[ -z "$chars" ]]; then
    echo "0"
    return 0
  fi
  # Rough heuristic: ~4 chars/token in English-ish text.
  echo $(((chars + 3) / 4))
}

token_level_emoji() {
  local tokens="${1:-0}"
  local yellow="${MILHOUSE_TOKEN_YELLOW:-20000}"
  local orange="${MILHOUSE_TOKEN_ORANGE:-40000}"
  local red="${MILHOUSE_TOKEN_RED:-60000}"
  if (( tokens < yellow )); then
    echo "🟢"
  elif (( tokens < orange )); then
    echo "🟡"
  elif (( tokens < red )); then
    echo "🟠"
  else
    echo "🔴"
  fi
}

format_duration_compact() {
  local seconds="${1:-0}"
  local m=$((seconds / 60))
  local s=$((seconds % 60))
  if (( m <= 0 )); then
    printf "%ss" "$s"
  else
    printf "%sm%02ss" "$m" "$s"
  fi
}

start_out_log_heartbeat() {
  # Args: workspace, iteration, model, prompt_chars
  local workspace="$1"
  local iteration="$2"
  local model="$3"
  local prompt_chars="${4:-0}"

  local interval="${MILHOUSE_LOG_HEARTBEAT_SECONDS:-120}" # 2 minutes default
  if [[ -z "$interval" ]] || (( interval <= 0 )); then
    interval="120"
  fi

  local prompt_tokens
  prompt_tokens="$(estimate_tokens_from_chars "$prompt_chars")"
  local tok_emoji
  tok_emoji="$(token_level_emoji "$prompt_tokens")"

  log_out "$workspace" "Heartbeat: every ${interval}s (elapsed + token level). Prompt: ${tok_emoji} ~${prompt_tokens} tokens"

  (
    local start_epoch
    start_epoch="$(date +%s)"
    while true; do
      sleep "$interval" || exit 0
      local now elapsed
      now="$(date +%s)"
      elapsed=$((now - start_epoch))
      local elapsed_s
      elapsed_s="$(format_duration_compact "$elapsed")"

      # Prompt token level is a proxy for context size; it won't reflect hidden system tokens,
      # but it's good enough for a “green/yellow/orange/red” signal.
      local emoji
      emoji="$(token_level_emoji "$prompt_tokens")"

      local nudge=""
      if [[ "$emoji" == "🟠" ]]; then
        nudge=" — getting heavy; consider resetting soon"
      elif [[ "$emoji" == "🔴" ]]; then
        nudge=" — very heavy; reset strongly recommended"
      fi

      log_out "$workspace" "⏱️ ${elapsed_s} | tokens ${emoji} ~${prompt_tokens} (prompt)${nudge}"
    done
  ) &

  echo $!
}

stop_out_log_heartbeat() {
  # Args: pid
  local pid="${1:-}"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
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
  --stop-after  Ask a running Milhouse to stop after current iteration
  --stop-now    Stop a running Milhouse immediately (kills agent), then sync TODO
  --status      Show whether Milhouse is running in this workspace
  --help        Show this help message

ARGUMENTS
  workspace     Path to project directory (default: current directory)

ENVIRONMENT VARIABLES
  MILHOUSE_MODEL              AI model to use (default: opus-4.5-thinking)
  MILHOUSE_MAX_ITERATIONS     Maximum iterations before stopping (default: 20)
  MILHOUSE_ROTATION_INTERVAL  Fixed rotation every N iterations (default: 5)
  MILHOUSE_AGENT_OUTPUT_MODE  plain (default) or stream-json (also writes .milhouse/out.stream.jsonl)
  MILHOUSE_LOG_HEARTBEAT_SECONDS
                             How often to write a simple progress line to .milhouse/out.txt (default: 120)
  MILHOUSE_TOKEN_YELLOW       Prompt token estimate threshold for 🟡 (default: 20000)
  MILHOUSE_TOKEN_ORANGE       Prompt token estimate threshold for 🟠 (default: 40000)
  MILHOUSE_TOKEN_RED          Prompt token estimate threshold for 🔴 (default: 60000)

EXAMPLES
  ./milhouse.sh                              # Loop mode, current directory
  ./milhouse.sh --once                       # Single iteration, then stop
  ./milhouse.sh --loop /path/to/project      # Loop mode, specific project
  ./milhouse.sh --setup                      # Interactive configuration
  ./milhouse.sh --stop-after                 # Stop after current iteration
  ./milhouse.sh --stop-now /path/to/project  # Stop immediately (kill agent)
  ./milhouse.sh --status                     # Show running status
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
    --stop-after)
      MODE="stop-after"
      shift
      ;;
    --stop-now)
      MODE="stop-now"
      shift
      ;;
    --status)
      MODE="status"
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
  --stop-after  Stop after current iteration
  --stop-now    Stop immediately (kill agent)
  --status      Show running status
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

# =============================================================================
# STOP MECHANISM (Operator control)
# =============================================================================

# Per-workspace control files (all live under .milhouse/)
milhouse_pid_file() { echo "$1/.milhouse/milhouse.pid"; }
milhouse_stop_after_file() { echo "$1/.milhouse/stop.after"; }
milhouse_stop_now_file() { echo "$1/.milhouse/stop.now"; }
milhouse_stop_reason_file() { echo "$1/.milhouse/stop.reason"; }

# Runtime state used by signal handlers (best-effort; kept simple)
CURRENT_WORKSPACE=""
CURRENT_AGENT_PID=""
CURRENT_AGENT_PIPE_PID=""
CURRENT_AGENT_PIPE_FIFO=""
CURRENT_HEARTBEAT_PID=""

is_pid_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

read_running_pid() {
  local workspace="$1"
  local pid_file
  pid_file="$(milhouse_pid_file "$workspace")"
  [[ -f "$pid_file" ]] || { echo ""; return 1; }
  local pid
  pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "$pid"
    return 0
  fi
  echo ""
  return 1
}

write_running_pid() {
  local workspace="$1"
  local pid_file
  pid_file="$(milhouse_pid_file "$workspace")"
  mkdir -p "$workspace/.milhouse"
  echo "$$" > "$pid_file"
}

clear_running_pid() {
  local workspace="$1"
  local pid_file
  pid_file="$(milhouse_pid_file "$workspace")"
  rm -f "$pid_file" >/dev/null 2>&1 || true
}

clear_stop_requests() {
  local workspace="$1"
  rm -f "$(milhouse_stop_after_file "$workspace")" >/dev/null 2>&1 || true
  rm -f "$(milhouse_stop_now_file "$workspace")" >/dev/null 2>&1 || true
  rm -f "$(milhouse_stop_reason_file "$workspace")" >/dev/null 2>&1 || true
}

request_stop_after() {
  local workspace="$1"
  local reason="${2:-requested}"
  mkdir -p "$workspace/.milhouse"
  echo "$reason" > "$(milhouse_stop_reason_file "$workspace")"
  : > "$(milhouse_stop_after_file "$workspace")"
}

request_stop_now() {
  local workspace="$1"
  local reason="${2:-requested}"
  mkdir -p "$workspace/.milhouse"
  echo "$reason" > "$(milhouse_stop_reason_file "$workspace")"
  : > "$(milhouse_stop_now_file "$workspace")"
}

get_stop_request() {
  local workspace="$1"
  if [[ -f "$(milhouse_stop_now_file "$workspace")" ]]; then
    echo "now"
    return 0
  fi
  if [[ -f "$(milhouse_stop_after_file "$workspace")" ]]; then
    echo "after"
    return 0
  fi
  echo ""
  return 1
}

ensure_single_instance() {
  local workspace="$1"
  local pid
  pid="$(read_running_pid "$workspace" || true)"
  if [[ -n "$pid" ]] && is_pid_running "$pid"; then
    show_error "Milhouse is already running in this workspace" \
      "Workspace: $workspace
PID: $pid

Fix:
  - Check status: $0 --status \"$workspace\"
  - Stop after current iteration: $0 --stop-after \"$workspace\"
  - Stop immediately: $0 --stop-now \"$workspace\""
    return 1
  fi
  return 0
}

kill_pid_with_timeout() {
  # Args: pid, label, timeout_seconds
  local pid="${1:-}"
  local label="${2:-process}"
  local timeout="${3:-2}"
  [[ -n "$pid" ]] || return 0
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0

  if ! is_pid_running "$pid"; then
    return 0
  fi

  kill -TERM "$pid" >/dev/null 2>&1 || true
  local waited=0
  while is_pid_running "$pid" && [[ $waited -lt $timeout ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if is_pid_running "$pid"; then
    kill -KILL "$pid" >/dev/null 2>&1 || true
  fi
}

kill_current_agent_processes() {
  # Best-effort: stop the in-flight cursor-agent and its companion pipeline.
  if [[ -n "$CURRENT_AGENT_PID" ]]; then
    kill_pid_with_timeout "$CURRENT_AGENT_PID" "cursor-agent" 2
  fi
  if [[ -n "$CURRENT_AGENT_PIPE_PID" ]]; then
    kill_pid_with_timeout "$CURRENT_AGENT_PIPE_PID" "stream pipeline" 2
  fi
  if [[ -n "$CURRENT_AGENT_PIPE_FIFO" ]] && [[ -p "$CURRENT_AGENT_PIPE_FIFO" ]]; then
    rm -f "$CURRENT_AGENT_PIPE_FIFO" >/dev/null 2>&1 || true
  fi
  CURRENT_AGENT_PID=""
  CURRENT_AGENT_PIPE_PID=""
  CURRENT_AGENT_PIPE_FIFO=""
}

cleanup_on_exit() {
  local code=$?
  if [[ -n "$CURRENT_WORKSPACE" ]]; then
    # Stop any active heartbeat and agent subprocesses
    stop_out_log_heartbeat "$CURRENT_HEARTBEAT_PID"
    CURRENT_HEARTBEAT_PID=""
    kill_current_agent_processes

    # Best-effort: sync progress back to TODO.md before exiting
    sync_task_progress_to_todo "$CURRENT_WORKSPACE" || true

    clear_running_pid "$CURRENT_WORKSPACE"
    clear_stop_requests "$CURRENT_WORKSPACE"
  fi
  return "$code"
}

handle_interrupt() {
  # Ctrl+C handler: offer a choice when possible; default to "stop now" if not.
  local workspace="$CURRENT_WORKSPACE"
  [[ -n "$workspace" ]] || exit 130

  # If a stop is already requested, escalate to immediate stop.
  if [[ -n "$(get_stop_request "$workspace" || true)" ]]; then
    request_stop_now "$workspace" "forced (second interrupt)"
    show_warning "Stopping immediately (forced)..."
    log_out "$workspace" "Stop: immediate (forced)"
    kill_current_agent_processes
    exit 130
  fi

  local choice="stop-now"
  if [[ "$HAS_GUM" == "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
    choice="$(gum choose --header "Stop Milhouse?" \
      "Stop after current iteration (safe)" \
      "Stop immediately (kill agent)" \
      "Continue running")" || choice="Stop immediately (kill agent)"
    if [[ "$choice" == "Continue running" ]]; then
      show_info "Continuing..."
      log_out "$workspace" "Stop: cancelled (continue running)"
      return 0
    fi
    if [[ "$choice" == "Stop after current iteration (safe)" ]]; then
      request_stop_after "$workspace" "requested via Ctrl+C (after iteration)"
      show_warning "Will stop after the current iteration finishes."
      log_out "$workspace" "Stop: after current iteration (requested via Ctrl+C)"
      return 0
    fi
    # Fallthrough: immediate
  fi

  request_stop_now "$workspace" "requested via Ctrl+C (immediate)"
  show_warning "Stopping immediately..."
  log_out "$workspace" "Stop: immediate (requested via Ctrl+C)"
  kill_current_agent_processes
  exit 130
}

handle_terminate() {
  # SIGTERM handler: always stop immediately (no prompts).
  local workspace="$CURRENT_WORKSPACE"
  [[ -n "$workspace" ]] || exit 143
  request_stop_now "$workspace" "terminated (SIGTERM)"
  show_warning "Stopping immediately (SIGTERM)..."
  log_out "$workspace" "Stop: immediate (SIGTERM)"
  kill_current_agent_processes
  exit 143
}

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

  # Initialize per-task-run id if missing (used to reset iteration across new task runs)
  if [[ ! -f "$milhouse_dir/task_run_id" ]]; then
    echo "0" > "$milhouse_dir/task_run_id"
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
#          "NO_TASK_FILE" if missing
#          "NO_CRITERIA" if file has zero checkboxes (treated as not runnable)
check_task_complete() {
  local workspace="$1"
  local task_file="$workspace/MILHOUSE_TASK.md"
  
  if [[ ! -f "$task_file" ]]; then
    echo "NO_TASK_FILE"
    return 1
  fi

  # Count all checkboxes and unchecked checkboxes.
  # Matches: "- [ ]", "* [x]", "1. [ ]", etc.
  local total unchecked
  total=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[(x| )\]' "$task_file" 2>/dev/null) || total=0
  unchecked=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[ \]' "$task_file" 2>/dev/null) || unchecked=0

  if [[ "$total" -eq 0 ]]; then
    echo "NO_CRITERIA"
    return 1
  fi

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
# TASK RUN ID (separates iteration counters across new MILHOUSE_TASK.md runs)
# =============================================================================

get_task_run_id() {
  local workspace="$1"
  local f="$workspace/.milhouse/task_run_id"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "0"
  fi
}

set_task_run_id() {
  local workspace="$1"
  local id="${2:-0}"
  mkdir -p "$workspace/.milhouse"
  echo "$id" > "$workspace/.milhouse/task_run_id"
}

bump_task_run_id() {
  local workspace="$1"
  local cur
  cur="$(get_task_run_id "$workspace")"
  if [[ -z "$cur" ]] || ! [[ "$cur" =~ ^[0-9]+$ ]]; then
    cur="0"
  fi
  local next=$((cur + 1))
  set_task_run_id "$workspace" "$next"
  echo "$next"
}

reset_iteration_for_new_task_run() {
  local workspace="$1"
  local new_id
  new_id="$(bump_task_run_id "$workspace")"
  set_iteration "$workspace" "0"
  show_info "Starting new task run (run id: $new_id). Iteration counter reset."
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
  elif [[ $max_pct -lt 80 ]]; then
    echo "🟡"
  elif [[ $max_pct -lt 95 ]]; then
    echo "🟠"
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
  if [[ $max_pct -ge 95 ]]; then
    note="reset strongly recommended"
  elif [[ $max_pct -ge 80 ]]; then
    note="reset soon"
  elif [[ $max_pct -ge 60 ]]; then
    note="getting busy"
  else
    note="healthy"
  fi

  local dur
  dur="$(format_duration_compact "$duration_seconds")"
  echo "$emoji Context: ~${max_pct}% | ${dur} | ${file_count} files | ${commit_count} commits | est used ~$used/$token_capacity — $note"
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
# Stores task file hash in .milhouse/.task_hash.{run_id}.{iteration}
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

  # Namespace by run id so a new task run doesn't inherit old hashes.
  local run_id
  run_id="$(get_task_run_id "$workspace")"
  if [[ -z "$run_id" ]] || ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    run_id="0"
  fi
  
  # Store current hash
  echo "$current_hash" > "$milhouse_dir/.task_hash.${run_id}.$current_iteration"
  
  # Check previous N iterations for same hash
  local unchanged_count=0
  local i=$((current_iteration - 1))
  local stop_at=$((current_iteration - stale_threshold))
  
  while [[ $i -ge $stop_at ]] && [[ $i -ge 0 ]]; do
    local prev_hash_file="$milhouse_dir/.task_hash.${run_id}.$i"
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
  local agent_output_mode="${MILHOUSE_AGENT_OUTPUT_MODE:-plain}" # plain|stream-json
  
  # Build prompt
  local prompt
  prompt=$(build_prompt "$workspace" "$iteration")
  local prompt_chars="${#prompt}"
  
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
  log_out "$workspace" "Prompt length: ${prompt_chars} chars"
  if [[ "$agent_output_mode" == "stream-json" ]]; then
    log_out "$workspace" "Log mode: stream-json (cleaned text + raw stream saved)"
    log_out "$workspace" "Raw agent stream: $raw_stream_file"
  else
    log_out "$workspace" "Log mode: plain (clean, readable log)"
    log_out "$workspace" "Tip: set MILHOUSE_AGENT_OUTPUT_MODE=stream-json for extra debug data"
  fi
  
  # Execute the agent.
  #
  # Note: we intentionally avoid wrapping cursor-agent with `gum spin` here.
  # In practice, spinner wrappers can cause “Aborting operation...” or apparent hangs.
  # The “Follow along” tail command is the preferred live view.
  echo "Agent working on iteration $iteration..."
  CURRENT_HEARTBEAT_PID="$(start_out_log_heartbeat "$workspace" "$iteration" "$model" "$prompt_chars")"
  local exit_code=0

  # Reset stop/runtime tracking for this iteration
  CURRENT_AGENT_PID=""
  CURRENT_AGENT_PIPE_PID=""
  CURRENT_AGENT_PIPE_FIFO=""

  if [[ "$agent_output_mode" == "stream-json" ]]; then
    # Stream-json mode:
    # - cursor-agent writes to a FIFO (so we can track its PID and kill it reliably)
    # - a background pipeline tees to raw stream + cleaned out.txt
    local fifo="$workspace/.milhouse/.agent.stream.fifo"
    rm -f "$fifo" >/dev/null 2>&1 || true
    mkfifo "$fifo"
    CURRENT_AGENT_PIPE_FIFO="$fifo"

    # Tee raw stream + write cleaned text in background.
    ( tee -a "$raw_stream_file" < "$fifo" | clean_cursor_agent_stream >> "$output_file" ) &
    CURRENT_AGENT_PIPE_PID="$!"

    # Run cursor-agent in background so stop handlers can kill it.
    cursor-agent -p --force \
      --output-format stream-json \
      --stream-partial-output \
      --workspace "$workspace" \
      --model "$model" \
      "$prompt" > "$fifo" 2>&1 &
    CURRENT_AGENT_PID="$!"

    exit_code=0
    wait "$CURRENT_AGENT_PID" || exit_code=$?

    # Let the tee/clean pipeline flush and exit.
    wait "$CURRENT_AGENT_PIPE_PID" >/dev/null 2>&1 || true
    rm -f "$fifo" >/dev/null 2>&1 || true
    CURRENT_AGENT_PIPE_FIFO=""
  else
    # Default: plain output. This avoids noisy JSON logs and is the most stable.
    cursor-agent -p --force \
      --workspace "$workspace" \
      --model "$model" \
      "$prompt" >> "$output_file" 2>&1 &
    CURRENT_AGENT_PID="$!"
    exit_code=0
    wait "$CURRENT_AGENT_PID" || exit_code=$?
  fi
  stop_out_log_heartbeat "$CURRENT_HEARTBEAT_PID"
  CURRENT_HEARTBEAT_PID=""
  CURRENT_AGENT_PID=""
  CURRENT_AGENT_PIPE_PID=""
  
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
  task_status=$(check_task_complete "$workspace" || true)
  
  if [[ "$task_status" == "COMPLETE" ]]; then
    local items
    items="$(list_unchecked_todo_items "$workspace")"
    if [[ -n "$items" ]]; then
      echo "⚠ MILHOUSE_TASK.md is complete, but TODO.md still has unchecked items."
      echo "Run again and choose tasks from TODO.md to start a new run."
      log_out "$workspace" "Status: COMPLETE (TODO.md still has unchecked items)"
    else
      echo "🎉 Task already complete! All criteria are checked."
      log_out "$workspace" "Status: COMPLETE (no work needed)"
    fi
    return 0
  fi

  if [[ "$task_status" == "NO_CRITERIA" ]]; then
    show_error "MILHOUSE_TASK.md has no checkbox criteria" \
      "Milhouse needs checkbox criteria to track progress.

Fix:
  - Delete or update MILHOUSE_TASK.md to include checkboxes
  - Or re-run and pick tasks from TODO.md to generate a new MILHOUSE_TASK.md"
    return 1
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

  # Announce current task (one line) before the agent runs
  show_task_start "$workspace"
  local completed_before
  completed_before="$(list_task_ids_by_state "$workspace" "x" || true)"
  
  echo "Follow along:"
  echo "  tail -f $output_file"
  echo ""
  log_out "$workspace" "Follow along: tail -f $output_file"
  
  run_agent_iteration "$workspace" "$iteration" "$model"
  local exit_code=$?
  
  # Keep TODO.md in sync with completed MILHOUSE_TASK.md items
  sync_task_progress_to_todo "$workspace"
  log_out "$workspace" "Synced MILHOUSE_TASK.md → TODO.md (best-effort)"

  # Announce any newly completed checklist items
  local completed_after
  completed_after="$(list_task_ids_by_state "$workspace" "x" || true)"
  if [[ -n "$completed_before" ]] || [[ -n "$completed_after" ]]; then
    local before_f after_f
    before_f="$(mktemp)"
    after_f="$(mktemp)"
    printf "%s\n" "$completed_before" | sort -u > "$before_f"
    printf "%s\n" "$completed_after" | sort -u > "$after_f"
    local new_ids
    new_ids="$(comm -13 "$before_f" "$after_f" || true)"
    rm -f "$before_f" "$after_f" >/dev/null 2>&1 || true
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      local one
      one="$(get_task_one_liner_for_id "$workspace" "$id" || true)"
      if [[ -z "$one" ]]; then
        one="$id"
      fi
      show_task_completed "$workspace" "$one"
    done <<< "$new_ids"
  fi
  
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
  task_status=$(check_task_complete "$workspace" || true)
  if [[ "$task_status" == "COMPLETE" ]]; then
    local items
    items="$(list_unchecked_todo_items "$workspace")"
    if [[ -n "$items" ]]; then
      echo "⚠ MILHOUSE_TASK.md is complete, but TODO.md still has unchecked items."
      echo "Re-run Milhouse and pick tasks from TODO.md to start a new run."
    else
      echo "🎉 Task already complete! All criteria are checked."
    fi
    return 0
  fi

  if [[ "$task_status" == "NO_CRITERIA" ]]; then
    show_error "MILHOUSE_TASK.md has no checkbox criteria" \
      "Milhouse needs checkbox criteria to track progress.

Fix:
  - Delete or update MILHOUSE_TASK.md to include checkboxes
  - Or re-run and pick tasks from TODO.md to generate a new MILHOUSE_TASK.md"
    return 1
  fi
  
  echo "🚀 Starting Milhouse loop..."
  echo ""
  echo "Follow along:"
  echo "  tail -f $output_file"
  echo ""
  echo "Stop controls:"
  echo "  Stop after current iteration: $0 --stop-after \"$workspace\""
  echo "  Stop immediately (kill agent): $0 --stop-now \"$workspace\""
  echo "  Or press Ctrl+C for a stop menu"
  echo ""
  log_out "$workspace" "Follow along: tail -f $output_file"
  log_out "$workspace" "Stop: $0 --stop-after \"$workspace\"  |  $0 --stop-now \"$workspace\""
  
  # Main loop
  while [[ $iteration -lt $max_iterations ]]; do
    # Stop-now request: exit immediately (best-effort sync happens in EXIT trap).
    if [[ "$(get_stop_request "$workspace" || true)" == "now" ]]; then
      show_warning "Stop requested: stopping immediately."
      log_out "$workspace" "Stop requested: immediate (loop will exit)"
      return 0
    fi
    # Stop-after request before an iteration starts: stop cleanly without starting another run.
    if [[ "$(get_stop_request "$workspace" || true)" == "after" ]]; then
      show_warning "Stop requested: stopping before starting the next iteration."
      log_out "$workspace" "Stop requested: after (before next iteration)"
      return 0
    fi

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
    
    # Announce current task (one line) before the agent runs
    show_task_start "$workspace"
    local completed_before
    completed_before="$(list_task_ids_by_state "$workspace" "x" || true)"

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

    # Announce any newly completed checklist items
    local completed_after
    completed_after="$(list_task_ids_by_state "$workspace" "x" || true)"
    if [[ -n "$completed_before" ]] || [[ -n "$completed_after" ]]; then
      local before_f after_f
      before_f="$(mktemp)"
      after_f="$(mktemp)"
      printf "%s\n" "$completed_before" | sort -u > "$before_f"
      printf "%s\n" "$completed_after" | sort -u > "$after_f"
      local new_ids
      new_ids="$(comm -13 "$before_f" "$after_f" || true)"
      rm -f "$before_f" "$after_f" >/dev/null 2>&1 || true
      while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        local one
        one="$(get_task_one_liner_for_id "$workspace" "$id" || true)"
        if [[ -z "$one" ]]; then
          one="$id"
        fi
        show_task_completed "$workspace" "$one"
      done <<< "$new_ids"
    fi
    
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
    task_status=$(check_task_complete "$workspace" || true)
    
    if [[ "$task_status" == "COMPLETE" ]]; then
      echo ""
      show_header "🎉 MILHOUSE COMPLETE! All criteria satisfied." 10
      echo ""
      show_success "Completed in $iteration iteration(s)."
      show_info "Check git log for detailed history."
      log_out "$workspace" "Status: COMPLETE"
      return 0
    fi

    # Stop-after request: finish the iteration, sync TODO, then exit.
    if [[ "$(get_stop_request "$workspace" || true)" == "after" ]]; then
      show_warning "Stop requested: stopping after current iteration."
      log_out "$workspace" "Stop requested: after current iteration (loop will exit)"
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
  task_status=$(check_task_complete "$workspace" || true)
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

  # Control-only modes (no agent run)
  case "$MODE" in
    status)
      mkdir -p "$WORKSPACE/.milhouse"
      local pid
      pid="$(read_running_pid "$WORKSPACE" || true)"
      if [[ -n "$pid" ]] && is_pid_running "$pid"; then
        show_success "Milhouse is running (PID: $pid)"
        local stop
        stop="$(get_stop_request "$WORKSPACE" || true)"
        if [[ -n "$stop" ]]; then
          show_warning "Stop requested: $stop"
        else
          show_info "Stop requested: none"
        fi
      else
        show_info "Milhouse is not running in this workspace."
      fi
      exit 0
      ;;
    stop-after)
      mkdir -p "$WORKSPACE/.milhouse"
      request_stop_after "$WORKSPACE" "requested via CLI (--stop-after)"
      show_success "Requested stop after current iteration."
      show_info "If Milhouse is running, it will stop after it finishes the current iteration and sync TODO."
      exit 0
      ;;
    stop-now)
      mkdir -p "$WORKSPACE/.milhouse"
      request_stop_now "$WORKSPACE" "requested via CLI (--stop-now)"
      local pid
      pid="$(read_running_pid "$WORKSPACE" || true)"
      if [[ -n "$pid" ]] && is_pid_running "$pid"; then
        show_warning "Stopping Milhouse now (PID: $pid)..."
        kill_pid_with_timeout "$pid" "milhouse" 2
      else
        show_warning "No running Milhouse PID found; syncing TODO anyway."
      fi
      # Even if the running process couldn't do its own cleanup, sync TODO now (best-effort).
      sync_task_progress_to_todo "$WORKSPACE" || true
      show_success "Stop-now complete (best-effort)."
      exit 0
      ;;
  esac
  
  # Check prerequisites first
  # Allow missing MILHOUSE_TASK.md: we can create it interactively.
  if ! check_prerequisites "$WORKSPACE" 0; then
    echo ""
    show_info "Fix the errors above and try again."
    exit 1
  fi
  
  # Initialize state directory
  init_state "$WORKSPACE"

  # Register this run for stop control + cleanup
  if ! ensure_single_instance "$WORKSPACE"; then
    exit 1
  fi
  CURRENT_WORKSPACE="$WORKSPACE"
  write_running_pid "$WORKSPACE"
  clear_stop_requests "$WORKSPACE"
  trap cleanup_on_exit EXIT
  trap handle_interrupt INT
  trap handle_terminate TERM
  
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
  --stop-after  Stop after current iteration
  --stop-now    Stop immediately (kill agent)
  --status      Show running status

Fix: Use a valid mode flag:
  $0 --loop
  $0 --once
  $0 --setup
  $0 --status
  $0 --stop-after
  $0 --stop-now"
      exit 1
      ;;
  esac
}

# Run main function
main
