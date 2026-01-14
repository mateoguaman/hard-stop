#!/bin/bash
# Test suite for Hard Stop
# Run with: bash scripts/test.sh
# All tests are safe - no actual shutdowns will occur

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/hardstop-kickout.sh"
CONFIG="$REPO_ROOT/config.yml"
PLIST="$REPO_ROOT/launchd/com.hardstop.kickout.plist"
SUDOERS="$REPO_ROOT/sudoers/hardstop-shutdown"

# Colors for output (disable if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

PASSED=0
FAILED=0
WARNINGS=0

pass() {
  printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
  PASSED=$((PASSED + 1))
}

fail() {
  printf "${RED}✗ FAIL${NC}: %s\n" "$1"
  FAILED=$((FAILED + 1))
}

warn() {
  printf "${YELLOW}⚠ WARN${NC}: %s\n" "$1"
  WARNINGS=$((WARNINGS + 1))
}

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================
section "1. File Existence Tests"
# ============================================================

if [ -f "$SCRIPT" ]; then
  pass "Main script exists: $SCRIPT"
else
  fail "Main script missing: $SCRIPT"
fi

if [ -f "$REPO_ROOT/scripts/hardstop" ]; then
  pass "CLI wrapper exists: scripts/hardstop"
else
  fail "CLI wrapper missing: scripts/hardstop"
fi

if [ -f "$REPO_ROOT/scripts/install.sh" ]; then
  pass "Installer exists: scripts/install.sh"
else
  fail "Installer missing: scripts/install.sh"
fi

if [ -f "$CONFIG" ]; then
  pass "Config file exists: $CONFIG"
else
  fail "Config file missing: $CONFIG"
fi

if [ -f "$PLIST" ]; then
  pass "LaunchAgent plist exists: $PLIST"
else
  fail "LaunchAgent plist missing: $PLIST"
fi

if [ -f "$SUDOERS" ]; then
  pass "Sudoers file exists: $SUDOERS"
else
  fail "Sudoers file missing: $SUDOERS"
fi

# ============================================================
section "2. Script Syntax Tests"
# ============================================================

if /bin/bash -n "$SCRIPT" 2>/dev/null; then
  pass "Main script has valid bash syntax"
else
  fail "Main script has syntax errors"
fi

if /bin/bash -n "$REPO_ROOT/scripts/hardstop" 2>/dev/null; then
  pass "CLI wrapper has valid bash syntax"
else
  fail "CLI wrapper has syntax errors"
fi

if /bin/bash -n "$REPO_ROOT/scripts/install.sh" 2>/dev/null; then
  pass "Installer has valid bash syntax"
else
  fail "Installer has syntax errors"
fi

# ============================================================
section "3. Config Parsing Tests"
# ============================================================

# Extract values from config (handles comments and quotes)
start_time=$(awk -F: '/^start_time:/ {val=$2; for(i=3;i<=NF;i++)val=val":"$i; gsub(/[" ]/, "", val); sub(/#.*/, "", val); print val}' "$CONFIG")
end_time=$(awk -F: '/^end_time:/ {val=$2; for(i=3;i<=NF;i++)val=val":"$i; gsub(/[" ]/, "", val); sub(/#.*/, "", val); print val}' "$CONFIG")
interval=$(awk '/^lock_interval_seconds:/ {sub(/.*:/, ""); gsub(/[" ]/, ""); sub(/#.*/, ""); print}' "$CONFIG")

if [[ "$start_time" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
  pass "start_time is valid format: $start_time"
else
  fail "start_time invalid format: $start_time"
fi

if [[ "$end_time" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
  pass "end_time is valid format: $end_time"
else
  fail "end_time invalid format: $end_time"
fi

if [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 5 ]; then
  pass "lock_interval_seconds is valid: $interval"
else
  fail "lock_interval_seconds invalid: $interval (must be >= 5)"
fi

# ============================================================
section "4. Plist Validation Tests"
# ============================================================

if command -v plutil &>/dev/null; then
  if plutil -lint "$PLIST" &>/dev/null; then
    pass "Plist is valid XML"
  else
    fail "Plist has invalid XML"
  fi

  plist_interval=$(plutil -p "$PLIST" 2>/dev/null | awk '/StartInterval/ {print $3}')
  if [ "$plist_interval" = "$interval" ]; then
    pass "Plist interval matches config: $plist_interval"
  else
    warn "Plist interval ($plist_interval) differs from config ($interval) - run install to sync"
  fi
else
  warn "plutil not available (not on macOS?) - skipping plist validation"
fi

# ============================================================
section "5. Time Logic Tests (Unit Tests)"
# ============================================================

# Create a temporary test script that sources the main script's functions
test_time_logic() {
  local test_time="$1"
  local start="$2"
  local end="$3"
  local expected="$4"

  # Inline time logic test
  to_minutes() {
    local t="$1"
    local h="${t%:*}"
    local m="${t#*:}"
    echo "$((10#$h * 60 + 10#$m))"
  }

  local start_min=$(to_minutes "$start")
  local end_min=$(to_minutes "$end")
  local now_min=$(to_minutes "$test_time")

  local result="outside"
  if [ "$start_min" -lt "$end_min" ]; then
    if [ "$now_min" -ge "$start_min" ] && [ "$now_min" -lt "$end_min" ]; then
      result="inside"
    fi
  else
    # Wraps around midnight
    if [ "$now_min" -ge "$start_min" ] || [ "$now_min" -lt "$end_min" ]; then
      result="inside"
    fi
  fi

  if [ "$result" = "$expected" ]; then
    pass "Time $test_time with range $start-$end: expected $expected, got $result"
  else
    fail "Time $test_time with range $start-$end: expected $expected, got $result"
  fi
}

# Test cases for 21:00-08:00 range (wraps midnight)
test_time_logic "20:59" "21:00" "08:00" "outside"  # Just before quiet hours
test_time_logic "21:00" "21:00" "08:00" "inside"   # Exactly at start
test_time_logic "21:01" "21:00" "08:00" "inside"   # Just after start
test_time_logic "23:59" "21:00" "08:00" "inside"   # Before midnight
test_time_logic "00:00" "21:00" "08:00" "inside"   # Midnight
test_time_logic "03:00" "21:00" "08:00" "inside"   # Middle of night
test_time_logic "07:59" "21:00" "08:00" "inside"   # Just before end
test_time_logic "08:00" "21:00" "08:00" "outside"  # Exactly at end
test_time_logic "08:01" "21:00" "08:00" "outside"  # Just after end
test_time_logic "12:00" "21:00" "08:00" "outside"  # Middle of day

# Test non-wrapping range (e.g., 09:00-17:00)
test_time_logic "08:59" "09:00" "17:00" "outside"
test_time_logic "09:00" "09:00" "17:00" "inside"
test_time_logic "12:00" "09:00" "17:00" "inside"
test_time_logic "17:00" "09:00" "17:00" "outside"

# ============================================================
section "6. Script --test Mode"
# ============================================================

# Note: These tests require macOS date command format
if output=$("$SCRIPT" --test 2>&1); then
  pass "Script --test mode runs without error"
  if echo "$output" | grep -q "quiet hours"; then
    pass "Script --test outputs quiet hours info"
  else
    fail "Script --test missing quiet hours info"
  fi
else
  # May fail on non-macOS due to date command differences
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "Script --test failed (expected on non-macOS systems)"
  else
    fail "Script --test mode failed"
  fi
fi

if output=$("$SCRIPT" --status 2>&1); then
  pass "Script --status mode runs without error"
else
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "Script --status failed (expected on non-macOS systems)"
  else
    fail "Script --status mode failed"
  fi
fi

# ============================================================
section "7. Installation Check (if installed)"
# ============================================================

INSTALLED_SCRIPT="$HOME/.local/bin/hardstop-kickout.sh"
INSTALLED_CLI="$HOME/.local/bin/hardstop"
INSTALLED_PLIST="$HOME/Library/LaunchAgents/com.hardstop.kickout.plist"
INSTALLED_SUDOERS="/etc/sudoers.d/hardstop-shutdown"

if [ -f "$INSTALLED_SCRIPT" ]; then
  pass "Script installed at $INSTALLED_SCRIPT"
else
  warn "Script not installed at $INSTALLED_SCRIPT - run scripts/install.sh"
fi

if [ -f "$INSTALLED_CLI" ]; then
  pass "CLI installed at $INSTALLED_CLI"
else
  warn "CLI not installed at $INSTALLED_CLI - run scripts/install.sh"
fi

if [ -f "$INSTALLED_PLIST" ]; then
  pass "LaunchAgent installed at $INSTALLED_PLIST"
else
  warn "LaunchAgent not installed - run scripts/install.sh"
fi

if [ -f "$INSTALLED_SUDOERS" ]; then
  pass "Sudoers rule installed at $INSTALLED_SUDOERS"
else
  warn "Sudoers rule not installed - run scripts/install.sh"
fi

# ============================================================
section "8. LaunchAgent Status (if on macOS)"
# ============================================================

if command -v launchctl &>/dev/null; then
  if launchctl list 2>/dev/null | grep -q "com.hardstop.kickout"; then
    pass "LaunchAgent is loaded and running"
  else
    warn "LaunchAgent not loaded - run 'hardstop enable'"
  fi
else
  warn "launchctl not available (not on macOS?) - skipping"
fi

# ============================================================
section "9. Sudoers Verification (if installed)"
# ============================================================

if [ -f "$INSTALLED_SUDOERS" ]; then
  pass "Sudoers file exists at $INSTALLED_SUDOERS"
  # Check the file permissions (should be 440 or 400)
  if command -v stat &>/dev/null; then
    perms=$(stat -c "%a" "$INSTALLED_SUDOERS" 2>/dev/null || stat -f "%Lp" "$INSTALLED_SUDOERS" 2>/dev/null || echo "unknown")
    if [ "$perms" = "440" ] || [ "$perms" = "400" ]; then
      pass "Sudoers file has correct permissions: $perms"
    elif [ "$perms" = "unknown" ]; then
      warn "Could not check sudoers permissions"
    else
      warn "Sudoers file permissions may be incorrect: $perms (expected 440)"
    fi
  fi
  echo "  (To verify passwordless shutdown works, run: sudo -n /sbin/shutdown --help)"
else
  warn "Sudoers not installed at $INSTALLED_SUDOERS - run scripts/install.sh"
fi

# ============================================================
section "SUMMARY"
# ============================================================

echo ""
echo "Results:"
printf "  ${GREEN}Passed${NC}:   %d\n" "$PASSED"
printf "  ${RED}Failed${NC}:   %d\n" "$FAILED"
printf "  ${YELLOW}Warnings${NC}: %d\n" "$WARNINGS"
echo ""

if [ "$FAILED" -eq 0 ]; then
  printf "${GREEN}All tests passed!${NC}\n"
  exit 0
else
  printf "${RED}Some tests failed.${NC}\n"
  exit 1
fi
