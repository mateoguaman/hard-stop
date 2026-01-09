#!/bin/bash
set -euo pipefail

CONFIG_DEFAULT="$HOME/.local/bin/hardstop-kickout.sh"
STATE_DIR="${HARDSTOP_STATE_DIR:-$HOME/Library/Application Support/hardstop}"
REPO_FILE="$HOME/.local/share/hardstop/repo_path"
CONFIG_YAML=""
AGENT_LABEL="com.hardstop.kickout"
SHOW_IDLE=0
LAST_LOCK_FILE="$STATE_DIR/last_lock_epoch.txt"

yaml_get() {
  local key="$1"
  if [ ! -f "$CONFIG_YAML" ]; then
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
  ' "$CONFIG_YAML"
}

get_var() {
  local key="$1"
  local val=""
  val="$(yaml_get "$key")"
  if [ -z "$val" ] && [ -f "$CONFIG_DEFAULT" ]; then
    val="$(/usr/bin/awk -F= -v k="$key" '
      $1 == k {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
        gsub(/^"/, "", $2); gsub(/"$/, "", $2);
        print $2; exit
      }
    ' "$CONFIG_DEFAULT")"
  fi
  echo "$val"
}

to_seconds() {
  local t="$1"
  local h="${t%:*}"
  local m="${t#*:}"
  echo "$((10#$h * 3600 + 10#$m * 60))"
}

fmt_mmss() {
  local total="$1"
  local min=$((total / 60))
  local sec=$((total % 60))
  /usr/bin/printf "%02d:%02d" "$min" "$sec"
}

is_loaded() {
  /bin/launchctl list | /usr/bin/grep -q "$AGENT_LABEL"
}

# Resolve config location (env > repo > state dir).
if [ -n "${HARDSTOP_CONFIG:-}" ]; then
  CONFIG_YAML="$HARDSTOP_CONFIG"
elif [ -f "$REPO_FILE" ]; then
  repo_root="$(/bin/cat "$REPO_FILE" 2>/dev/null || echo "")"
  if [ -n "$repo_root" ] && [ -f "$repo_root/config.yml" ]; then
    CONFIG_YAML="$repo_root/config.yml"
  fi
fi

if [ -z "$CONFIG_YAML" ]; then
  CONFIG_YAML="$STATE_DIR/config.yml"
fi

if [ ! -f "$CONFIG_DEFAULT" ] && [ ! -f "$CONFIG_YAML" ]; then
  echo ""
  exit 0
fi

START_TIME="$(get_var START_TIME)"
END_TIME="$(get_var END_TIME)"
PREWARN_MINUTES="$(get_var PREWARN_MINUTES)"
SHOW_IDLE_VAL="$(yaml_get show_idle)"
LOCK_INTERVAL="$(yaml_get lock_interval_seconds)"

START_TIME="${START_TIME:-22:00}"
END_TIME="${END_TIME:-09:00}"
PREWARN_MINUTES="${PREWARN_MINUTES:-5}"
if ! /usr/bin/printf "%s" "$LOCK_INTERVAL" | /usr/bin/grep -Eq '^[0-9]+$'; then
  LOCK_INTERVAL=60
fi
if [ "$SHOW_IDLE_VAL" = "true" ] || [ "$SHOW_IDLE_VAL" = "1" ] || [ "$SHOW_IDLE_VAL" = "yes" ]; then
  SHOW_IDLE=1
fi

now_h="$((10#$(/bin/date +%H)))"
now_m="$((10#$(/bin/date +%M)))"
now_s="$((10#$(/bin/date +%S)))"
now_epoch="$((10#$(/bin/date +%s)))"
now_sec=$((now_h * 3600 + now_m * 60 + now_s))

start_sec="$(to_seconds "$START_TIME")"
end_sec="$(to_seconds "$END_TIME")"

if [ "$start_sec" -lt "$end_sec" ]; then
  in_quiet=$((now_sec >= start_sec && now_sec < end_sec))
else
  in_quiet=$((now_sec >= start_sec || now_sec < end_sec))
fi

if [ "$now_sec" -le "$start_sec" ]; then
  until_start=$((start_sec - now_sec))
else
  until_start=$((86400 - now_sec + start_sec))
fi

next_lock="$LOCK_INTERVAL"

if [ -f "$LAST_LOCK_FILE" ]; then
  last_lock="$(/bin/cat "$LAST_LOCK_FILE" 2>/dev/null || echo "")"
  if [ -n "$last_lock" ]; then
    diff=$((last_lock + LOCK_INTERVAL - now_epoch))
    if [ "$diff" -gt 0 ] && [ "$diff" -le "$LOCK_INTERVAL" ]; then
      next_lock="$diff"
    fi
  fi
fi

icon="•"
color="#8E8E93"
countdown=""
phase="idle"

if ! is_loaded; then
  echo ""
  exit 0
elif [ "$in_quiet" -eq 1 ]; then
  icon="🔒"
  color="#E0E0E0"
  countdown="$(fmt_mmss "$next_lock")"
  phase="active"
elif [ "$until_start" -le $((PREWARN_MINUTES * 60)) ] && [ "$until_start" -gt 0 ]; then
  icon="⏳"
  color="#E0E0E0"
  countdown="$(fmt_mmss "$until_start")"
  phase="prewarn"
fi

if [ "$phase" = "idle" ] && [ "$SHOW_IDLE" -eq 0 ]; then
  echo ""
  exit 0
fi

if [ -n "$countdown" ]; then
  echo "$icon $countdown | color=$color"
else
  echo "$icon | color=$color"
fi

echo "---"
echo "State: $phase"
echo "Quiet hours: $START_TIME - $END_TIME"
if [ "$in_quiet" -eq 1 ]; then
  echo "Next lock in: $(fmt_mmss "$next_lock")"
elif [ "$until_start" -le $((PREWARN_MINUTES * 60)) ] && [ "$until_start" -gt 0 ]; then
  echo "Lock in: $(fmt_mmss "$until_start")"
else
  echo "Starts in: $(fmt_mmss "$until_start")"
fi
