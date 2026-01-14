#!/bin/bash
set -euo pipefail

# --- Configuration ---
# 24-hour time, local machine time zone.
START_TIME="21:00"
END_TIME="08:00"
GRACE_PERIOD=300  # seconds after boot before enforcing shutdown

STATE_DIR="${HARDSTOP_STATE_DIR:-$HOME/Library/Application Support/hardstop}"
REPO_FILE="$HOME/.local/share/hardstop/repo_path"
CONFIG_FILE=""
TEST_LIVE_FILE="$STATE_DIR/test_live_until"
TEST_LIVE_INTERVAL_FILE="$STATE_DIR/test_live_interval"

# --- Helpers ---

# Resolve config location (env > repo > state dir).
if [ -n "${HARDSTOP_CONFIG:-}" ]; then
  CONFIG_FILE="$HARDSTOP_CONFIG"
elif [ -f "$REPO_FILE" ]; then
  repo_root="$(/bin/cat "$REPO_FILE" 2>/dev/null || echo "")"
  if [ -n "$repo_root" ] && [ -f "$repo_root/config.yml" ]; then
    CONFIG_FILE="$repo_root/config.yml"
  fi
fi

if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE="$STATE_DIR/config.yml"
fi

yaml_get() {
  local key="$1"
  if [ ! -f "$CONFIG_FILE" ]; then
    return 0
  fi
  /usr/bin/awk -v k="$key" '
    $0 ~ /^[[:space:]]*#/ {next}
    {
      # Match key at start of line followed by colon
      if (match($0, "^[[:space:]]*" k "[[:space:]]*:")) {
        val = substr($0, RLENGTH + 1)
        # Strip leading whitespace
        gsub(/^[[:space:]]+/, "", val)
        # Handle double-quoted strings
        if (match(val, /^"[^"]*"/)) {
          val = substr(val, 2, RLENGTH - 2)
          print val
          exit
        }
        # Handle single-quoted strings
        if (match(val, /^'\''[^'\'']*'\''/)) {
          val = substr(val, 2, RLENGTH - 2)
          print val
          exit
        }
        # Unquoted value: take until comment or end of line
        gsub(/[[:space:]]*#.*$/, "", val)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val
        exit
      }
    }
  ' "$CONFIG_FILE"
}

apply_yaml_overrides() {
  local val

  val="$(yaml_get start_time)"
  if [ -n "$val" ]; then
    START_TIME="$val"
  fi

  val="$(yaml_get end_time)"
  if [ -n "$val" ]; then
    END_TIME="$val"
  fi

  val="$(yaml_get lock_interval_seconds)"
  if [ -n "$val" ]; then
    GRACE_PERIOD="$val"
  fi
}

apply_yaml_overrides

to_minutes() {
  local t="$1"
  local h="${t%:*}"
  local m="${t#*:}"
  echo "$((10#$h * 60 + 10#$m))"
}

get_uptime_seconds() {
  # Extract boot time from sysctl and calculate uptime
  local boot_sec now_sec
  boot_sec=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/awk '{print $4}' | /usr/bin/tr -d ',')
  now_sec=$(/bin/date +%s)
  echo $((now_sec - boot_sec))
}

in_grace_period() {
  local uptime effective_grace
  uptime=$(get_uptime_seconds)
  effective_grace=$(get_effective_grace_period)
  [ "$uptime" -lt "$effective_grace" ]
}

in_quiet_hours() {
  local start end now
  start="$(to_minutes "$START_TIME")"
  end="$(to_minutes "$END_TIME")"
  now="$(to_minutes "$(/bin/date +%H:%M)")"

  if [ "$start" -lt "$end" ]; then
    [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]
  else
    # Wraps around midnight (e.g., 21:00 to 08:00)
    [ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
  fi
}

# Check if we're in test-live mode (file exists and hasn't expired)
in_test_live_mode() {
  if [ ! -f "$TEST_LIVE_FILE" ]; then
    return 1
  fi

  local expire_time now_epoch
  expire_time=$(/bin/cat "$TEST_LIVE_FILE" 2>/dev/null || echo "0")
  now_epoch=$(/bin/date +%s)

  if [ "$now_epoch" -lt "$expire_time" ]; then
    return 0  # Still in test mode
  else
    # Test mode expired, clean up
    /bin/rm -f "$TEST_LIVE_FILE"
    /bin/rm -f "$TEST_LIVE_INTERVAL_FILE"
    return 1
  fi
}

# Get the effective grace period (uses test-live interval if in test mode)
get_effective_grace_period() {
  if [ -f "$TEST_LIVE_INTERVAL_FILE" ] && [ -f "$TEST_LIVE_FILE" ]; then
    # Check if test-live is still active
    local expire_time now_epoch
    expire_time=$(/bin/cat "$TEST_LIVE_FILE" 2>/dev/null || echo "0")
    now_epoch=$(/bin/date +%s)
    if [ "$now_epoch" -lt "$expire_time" ]; then
      /bin/cat "$TEST_LIVE_INTERVAL_FILE" 2>/dev/null || echo "$GRACE_PERIOD"
      return
    fi
  fi
  echo "$GRACE_PERIOD"
}

shutdown_now() {
  # Use sudo shutdown - the sudoers file allows this without password
  /usr/bin/sudo /sbin/shutdown -h now
}

main() {
  /bin/mkdir -p "$STATE_DIR"

  if [ "${1:-}" = "--test" ]; then
    echo "Test mode: would shutdown now if in quiet hours"
    if in_quiet_hours; then
      echo "Currently IN quiet hours ($START_TIME - $END_TIME)"
    else
      echo "Currently OUTSIDE quiet hours ($START_TIME - $END_TIME)"
    fi
    if in_test_live_mode; then
      local remaining=$(( $(/bin/cat "$TEST_LIVE_FILE") - $(/bin/date +%s) ))
      echo "TEST-LIVE MODE ACTIVE: ${remaining}s remaining"
    fi
    local uptime effective_grace
    uptime=$(get_uptime_seconds)
    effective_grace=$(get_effective_grace_period)
    if in_grace_period; then
      echo "IN GRACE PERIOD: ${uptime}s uptime < ${effective_grace}s grace (no shutdown yet)"
    else
      echo "Past grace period: ${uptime}s uptime >= ${effective_grace}s grace"
    fi
    exit 0
  fi

  if [ "${1:-}" = "--status" ]; then
    local uptime effective_grace
    uptime=$(get_uptime_seconds)
    effective_grace=$(get_effective_grace_period)
    if in_grace_period; then
      local grace_remaining=$((effective_grace - uptime))
      echo "IN GRACE PERIOD: ${grace_remaining}s remaining before enforcement"
    fi
    if in_test_live_mode; then
      local remaining=$(( $(/bin/cat "$TEST_LIVE_FILE") - $(/bin/date +%s) ))
      echo "TEST-LIVE MODE: ${remaining}s remaining - shutdown enforced after grace"
    elif in_quiet_hours; then
      echo "IN quiet hours ($START_TIME - $END_TIME) - shutdown enforced after grace"
    else
      echo "Outside quiet hours ($START_TIME - $END_TIME)"
    fi
    exit 0
  fi

  # Grace period: don't shutdown if system just booted
  if in_grace_period; then
    exit 0
  fi

  # Check test-live mode first (takes priority)
  if in_test_live_mode; then
    shutdown_now
    exit 0
  fi

  # Normal operation: shutdown if in quiet hours
  if in_quiet_hours; then
    shutdown_now
  fi
}

main "$@"
