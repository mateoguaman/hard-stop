#!/bin/bash
set -euo pipefail

# --- Configuration ---
# 24-hour time, local machine time zone.
START_TIME="21:00"
END_TIME="08:00"

STATE_DIR="${HARDSTOP_STATE_DIR:-$HOME/Library/Application Support/hardstop}"
REPO_FILE="$HOME/.local/share/hardstop/repo_path"
CONFIG_FILE=""

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
  /usr/bin/awk -F: -v k="$key" '
    $0 ~ /^[[:space:]]*#/ {next}
    NF >= 2 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
      if ($1 == k) {
        $1 = "";
        sub(/^:[[:space:]]*/, "", $0);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
        gsub(/^"/, "", $0); gsub(/"$/, "", $0);
        gsub(/^'\''/, "", $0); gsub(/'\''$/, "", $0);
        print $0; exit;
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
}

apply_yaml_overrides

to_minutes() {
  local t="$1"
  local h="${t%:*}"
  local m="${t#*:}"
  echo "$((10#$h * 60 + 10#$m))"
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

shutdown_now() {
  # Use sudo shutdown - the sudoers file allows this without password
  /usr/bin/sudo /sbin/shutdown -h now
}

main() {
  if [ "${1:-}" = "--test" ]; then
    echo "Test mode: would shutdown now if in quiet hours"
    if in_quiet_hours; then
      echo "Currently IN quiet hours ($START_TIME - $END_TIME)"
    else
      echo "Currently OUTSIDE quiet hours ($START_TIME - $END_TIME)"
    fi
    exit 0
  fi

  if [ "${1:-}" = "--status" ]; then
    if in_quiet_hours; then
      echo "IN quiet hours ($START_TIME - $END_TIME) - shutdown enforced"
    else
      echo "Outside quiet hours ($START_TIME - $END_TIME)"
    fi
    exit 0
  fi

  # Only shutdown if we're in quiet hours
  if in_quiet_hours; then
    shutdown_now
  fi
}

main "$@"
