#!/bin/bash
# Test script for Milhouse functions
# Tests Phases 1-4 functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MILHOUSE_SCRIPT="$SCRIPT_DIR/scripts/milhouse.sh"
TEST_DIR="$SCRIPT_DIR/test-workspace-phase1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

section() {
  echo ""
  echo -e "${YELLOW}=== $1 ===${NC}"
  echo ""
}

# Source the milhouse script to get access to functions
# We need to bypass the main execution
source_milhouse_functions() {
  # Create a temporary modified version that doesn't call main
  TEMP_SCRIPT=$(mktemp)
  # Comment out both the main function definition AND the call to main at the end
  sed -e 's/^main$/# main/' -e 's/^# Run main function$/# Run main function (disabled)/' "$MILHOUSE_SCRIPT" > "$TEMP_SCRIPT"
  # Also need to handle the WORKSPACE being set from pwd
  WORKSPACE="$TEST_DIR"
  source "$TEMP_SCRIPT" || true
  rm "$TEMP_SCRIPT"
}

# =============================================================================
# PHASE 1 TESTS: Basic Loop Functionality
# =============================================================================

test_phase1_state_files() {
  section "Phase 1: State File Management"
  
  # Test init_state creates correct directory structure
  rm -rf "$TEST_DIR/.milhouse"
  init_state "$TEST_DIR"
  
  if [[ -d "$TEST_DIR/.milhouse" ]]; then
    pass "init_state creates .milhouse directory"
  else
    fail "init_state should create .milhouse directory"
  fi
  
  if [[ -f "$TEST_DIR/.milhouse/iteration" ]]; then
    pass "init_state creates iteration file"
  else
    fail "init_state should create iteration file"
  fi
  
  if [[ -f "$TEST_DIR/.milhouse/progress.md" ]]; then
    pass "init_state creates progress.md"
  else
    fail "init_state should create progress.md"
  fi
  
  if [[ -f "$TEST_DIR/.milhouse/guardrails.md" ]]; then
    pass "init_state creates guardrails.md"
  else
    fail "init_state should create guardrails.md"
  fi
}

test_phase1_task_file() {
  section "Phase 1: Task File Reading"
  
  # Test read_task_file
  local counts
  counts=$(read_task_file "$TEST_DIR")
  
  if [[ "$counts" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    pass "read_task_file returns correct format (total:done:remaining)"
  else
    fail "read_task_file should return format total:done:remaining, got: $counts"
  fi
  
  # Test check_task_complete
  local status
  status=$(check_task_complete "$TEST_DIR")
  
  if [[ "$status" == "INCOMPLETE:1" ]]; then
    pass "check_task_complete correctly detects incomplete task"
  else
    fail "check_task_complete should return INCOMPLETE:1, got: $status"
  fi
  
  # Mark task complete and test again
  sed -i '' 's/\[ \]/[x]/g' "$TEST_DIR/MILHOUSE_TASK.md"
  status=$(check_task_complete "$TEST_DIR")
  
  if [[ "$status" == "COMPLETE" ]]; then
    pass "check_task_complete correctly detects complete task"
  else
    fail "check_task_complete should return COMPLETE, got: $status"
  fi
  
  # Restore incomplete state
  sed -i '' 's/\[x\]/[ ]/g' "$TEST_DIR/MILHOUSE_TASK.md"
}

test_phase1_iteration_counter() {
  section "Phase 1: Iteration Counter"
  
  # Reset iteration
  set_iteration "$TEST_DIR" 0
  
  local iter
  iter=$(get_iteration "$TEST_DIR")
  if [[ "$iter" == "0" ]]; then
    pass "get_iteration returns 0 after reset"
  else
    fail "get_iteration should return 0, got: $iter"
  fi
  
  # Increment
  iter=$(increment_iteration "$TEST_DIR")
  if [[ "$iter" == "1" ]]; then
    pass "increment_iteration returns 1 after first increment"
  else
    fail "increment_iteration should return 1, got: $iter"
  fi
  
  iter=$(get_iteration "$TEST_DIR")
  if [[ "$iter" == "1" ]]; then
    pass "get_iteration returns 1 after increment"
  else
    fail "get_iteration should return 1 after increment, got: $iter"
  fi
}

test_phase1_fixed_rotation() {
  section "Phase 1: Fixed Rotation"
  
  # Test fixed rotation at intervals
  if should_rotate_fixed 5 5; then
    pass "should_rotate_fixed triggers at iteration 5 (5%5=0)"
  else
    fail "should_rotate_fixed should trigger at iteration 5"
  fi
  
  if should_rotate_fixed 10 5; then
    pass "should_rotate_fixed triggers at iteration 10 (10%5=0)"
  else
    fail "should_rotate_fixed should trigger at iteration 10"
  fi
  
  if ! should_rotate_fixed 3 5; then
    pass "should_rotate_fixed does NOT trigger at iteration 3"
  else
    fail "should_rotate_fixed should NOT trigger at iteration 3"
  fi
  
  if ! should_rotate_fixed 0 5; then
    pass "should_rotate_fixed does NOT trigger at iteration 0"
  else
    fail "should_rotate_fixed should NOT trigger at iteration 0"
  fi
}

# =============================================================================
# PHASE 2 TESTS: Smart Rotation
# =============================================================================

test_phase2_time_rotation() {
  section "Phase 2: Time-Based Rotation"
  
  # Test time rotation threshold (1800 seconds = 30 minutes)
  if should_rotate_time 2000 1800; then
    pass "should_rotate_time triggers when duration (2000) > threshold (1800)"
  else
    fail "should_rotate_time should trigger when duration exceeds threshold"
  fi
  
  if ! should_rotate_time 1000 1800; then
    pass "should_rotate_time does NOT trigger when duration (1000) < threshold (1800)"
  else
    fail "should_rotate_time should NOT trigger when duration below threshold"
  fi
}

test_phase2_file_rotation() {
  section "Phase 2: File-Based Rotation"
  
  if should_rotate_files 60 50; then
    pass "should_rotate_files triggers when files (60) > threshold (50)"
  else
    fail "should_rotate_files should trigger when files exceed threshold"
  fi
  
  if ! should_rotate_files 30 50; then
    pass "should_rotate_files does NOT trigger when files (30) < threshold (50)"
  else
    fail "should_rotate_files should NOT trigger when files below threshold"
  fi
}

test_phase2_commit_rotation() {
  section "Phase 2: Commit-Based Rotation"
  
  if should_rotate_commits 15 10; then
    pass "should_rotate_commits triggers when commits (15) > threshold (10)"
  else
    fail "should_rotate_commits should trigger when commits exceed threshold"
  fi
  
  if ! should_rotate_commits 5 10; then
    pass "should_rotate_commits does NOT trigger when commits (5) < threshold (10)"
  else
    fail "should_rotate_commits should NOT trigger when commits below threshold"
  fi
}

test_phase2_combined_rotation() {
  section "Phase 2: Combined Rotation (should_rotate)"
  
  # Test fixed rotation reason
  local reason
  reason=$(should_rotate 0 0 0 5 5)
  if [[ "$reason" == *"fixed"* ]]; then
    pass "should_rotate returns 'fixed' reason at iteration 5"
  else
    fail "should_rotate should return fixed reason, got: $reason"
  fi
  
  # Test time rotation reason
  reason=$(should_rotate 2000 0 0 1 5 1800 50 10)
  if [[ "$reason" == *"time"* ]]; then
    pass "should_rotate returns 'time' reason when duration exceeds threshold"
  else
    fail "should_rotate should return time reason, got: $reason"
  fi
  
  # Test no rotation
  reason=$(should_rotate 100 10 2 1 5 1800 50 10)
  if [[ -z "$reason" ]]; then
    pass "should_rotate returns empty when no rotation needed"
  else
    fail "should_rotate should return empty, got: $reason"
  fi
}

# =============================================================================
# PHASE 3 TESTS: Gutter Detection
# =============================================================================

test_phase3_time_limit() {
  section "Phase 3: Time Limit Detection"
  
  # Test time limit (3600 seconds = 1 hour)
  if check_time_limit 4000 3600; then
    pass "check_time_limit detects gutter when duration (4000) > limit (3600)"
  else
    fail "check_time_limit should detect gutter when duration exceeds limit"
  fi
  
  if ! check_time_limit 2000 3600; then
    pass "check_time_limit does NOT detect gutter when duration (2000) < limit (3600)"
  else
    fail "check_time_limit should NOT detect gutter when duration below limit"
  fi
}

test_phase3_agent_signal() {
  section "Phase 3: Agent Signal Detection"
  
  # Create test output file with gutter signal
  local test_out="$TEST_DIR/.milhouse/test_gutter_out.txt"
  mkdir -p "$TEST_DIR/.milhouse"
  echo "Some output" > "$test_out"
  echo "<milhouse>GUTTER</milhouse>" >> "$test_out"
  
  if check_agent_gutter_signal "$test_out"; then
    pass "check_agent_gutter_signal detects <milhouse>GUTTER</milhouse> signal"
  else
    fail "check_agent_gutter_signal should detect gutter signal"
  fi
  
  # Test without signal
  echo "Normal output without signal" > "$test_out"
  
  if ! check_agent_gutter_signal "$test_out"; then
    pass "check_agent_gutter_signal does NOT detect when signal absent"
  else
    fail "check_agent_gutter_signal should NOT detect when signal absent"
  fi
  
  rm -f "$test_out"
}

test_phase3_task_stale() {
  section "Phase 3: Task File Stale Detection"
  
  # Setup: Create iteration hash files for last 3 iterations (same hash)
  mkdir -p "$TEST_DIR/.milhouse"
  local task_hash
  task_hash=$(shasum -a 256 "$TEST_DIR/MILHOUSE_TASK.md" | cut -d' ' -f1)
  
  echo "$task_hash" > "$TEST_DIR/.milhouse/.task_hash.1"
  echo "$task_hash" > "$TEST_DIR/.milhouse/.task_hash.2"
  echo "$task_hash" > "$TEST_DIR/.milhouse/.task_hash.3"
  
  # Test stale detection (unchanged for 2+ iterations)
  if check_task_file_stale "$TEST_DIR" 3 "MILHOUSE_TASK.md" 2; then
    pass "check_task_file_stale detects unchanged task file (2+ iterations)"
  else
    fail "check_task_file_stale should detect stale task file"
  fi
  
  # Test not stale (iteration too early)
  if ! check_task_file_stale "$TEST_DIR" 1 "MILHOUSE_TASK.md" 2; then
    pass "check_task_file_stale does NOT detect at iteration 1 (too early)"
  else
    fail "check_task_file_stale should NOT detect at iteration 1"
  fi
  
  # Cleanup
  rm -f "$TEST_DIR/.milhouse/.task_hash."*
}

# =============================================================================
# PHASE 4 TESTS: UI and Fallback
# =============================================================================

test_phase4_help_text() {
  section "Phase 4: Help Text"
  
  local help_output
  help_output=$("$MILHOUSE_SCRIPT" --help 2>&1)
  
  if [[ "$help_output" == *"USAGE"* ]]; then
    pass "Help text includes USAGE section"
  else
    fail "Help text should include USAGE section"
  fi
  
  if [[ "$help_output" == *"MODES"* ]]; then
    pass "Help text includes MODES section"
  else
    fail "Help text should include MODES section"
  fi
  
  if [[ "$help_output" == *"ENVIRONMENT VARIABLES"* ]]; then
    pass "Help text includes ENVIRONMENT VARIABLES section"
  else
    fail "Help text should include ENVIRONMENT VARIABLES section"
  fi
  
  if [[ "$help_output" == *"EXAMPLES"* ]]; then
    pass "Help text includes EXAMPLES section"
  else
    fail "Help text should include EXAMPLES section"
  fi
}

test_phase4_error_handling() {
  section "Phase 4: Error Handling"
  
  # Test unknown option error
  local error_output
  error_output=$("$MILHOUSE_SCRIPT" --invalid-option 2>&1) || true
  
  if [[ "$error_output" == *"Error"* ]] && [[ "$error_output" == *"Unknown option"* ]]; then
    pass "Unknown option produces clear error message"
  else
    fail "Unknown option should produce clear error message"
  fi
  
  if [[ "$error_output" == *"Valid options"* ]]; then
    pass "Error message includes valid options"
  else
    fail "Error message should include valid options"
  fi
}

test_phase4_gum_detection() {
  section "Phase 4: Gum Detection"
  
  # Gum should be detected
  if [[ "$HAS_GUM" == "true" ]]; then
    pass "HAS_GUM is true when gum is installed"
  else
    fail "HAS_GUM should be true when gum is installed"
  fi
  
  # Test check_gum function
  if check_gum; then
    pass "check_gum returns 0 when gum is available"
  else
    fail "check_gum should return 0 when gum is available"
  fi
}

test_phase4_output_helpers() {
  section "Phase 4: Output Helpers"
  
  # Test that output helpers don't crash (visual inspection needed for formatting)
  local output
  
  output=$(show_error "Test error" "Test details" 2>&1)
  if [[ "$output" == *"Error"* ]] && [[ "$output" == *"Test error"* ]]; then
    pass "show_error displays error message"
  else
    fail "show_error should display error message"
  fi
  
  output=$(show_success "Test success" 2>&1)
  if [[ "$output" == *"Test success"* ]]; then
    pass "show_success displays message"
  else
    fail "show_success should display message"
  fi
  
  output=$(show_warning "Test warning" 2>&1)
  if [[ "$output" == *"Test warning"* ]]; then
    pass "show_warning displays message"
  else
    fail "show_warning should display message"
  fi
  
  output=$(show_info "Test info" 2>&1)
  if [[ "$output" == *"Test info"* ]]; then
    pass "show_info displays message"
  else
    fail "show_info should display message"
  fi
  
  output=$(show_progress 1 2 5 3 2>&1)
  if [[ "$output" == *"Iteration"* ]] && [[ "$output" == *"criteria"* ]]; then
    pass "show_progress displays progress info"
  else
    fail "show_progress should display progress info"
  fi
}

test_phase4_fallback() {
  section "Phase 4: Fallback (Without Gum)"
  
  # Temporarily disable gum
  local OLD_HAS_GUM="$HAS_GUM"
  HAS_GUM="false"
  
  local output
  
  output=$(show_error "Fallback test" "Details" 2>&1)
  if [[ "$output" == *"Error"* ]]; then
    pass "show_error works without gum (fallback)"
  else
    fail "show_error fallback should work"
  fi
  
  output=$(show_success "Fallback success" 2>&1)
  if [[ "$output" == *"Fallback success"* ]]; then
    pass "show_success works without gum (fallback)"
  else
    fail "show_success fallback should work"
  fi
  
  output=$(show_progress 1 2 5 3 2>&1)
  if [[ "$output" == *"Iteration"* ]]; then
    pass "show_progress works without gum (fallback)"
  else
    fail "show_progress fallback should work"
  fi
  
  # Restore gum
  HAS_GUM="$OLD_HAS_GUM"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

main() {
  echo ""
  echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║         Milhouse Test Suite - Phases 1-4                          ║${NC}"
  echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════╝${NC}"
  
  # Source functions
  source_milhouse_functions
  
  # Ensure test directory exists
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  
  # If MILHOUSE_TASK.md doesn't exist, create it
  if [[ ! -f "$TEST_DIR/MILHOUSE_TASK.md" ]]; then
    cat > "$TEST_DIR/MILHOUSE_TASK.md" << 'EOF'
# Test Task for Phase 1

## Goal
Verify basic Milhouse loop functionality.

## Completion criteria
- [ ] Create file hello.txt with content "Phase 1 test"

## Done
When all checkboxes above are `[x]`, output:
`<milhouse>COMPLETE</milhouse>`
EOF
  fi
  
  # Run Phase 1 tests
  test_phase1_state_files
  test_phase1_task_file
  test_phase1_iteration_counter
  test_phase1_fixed_rotation
  
  # Run Phase 2 tests
  test_phase2_time_rotation
  test_phase2_file_rotation
  test_phase2_commit_rotation
  test_phase2_combined_rotation
  
  # Run Phase 3 tests
  test_phase3_time_limit
  test_phase3_agent_signal
  test_phase3_task_stale
  
  # Run Phase 4 tests
  test_phase4_help_text
  test_phase4_error_handling
  test_phase4_gum_detection
  test_phase4_output_helpers
  test_phase4_fallback
  
  # Summary
  echo ""
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
  echo ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

main "$@"
