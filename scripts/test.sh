#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(/usr/bin/mktemp -d)"
state_dir="$tmp_dir/state"
config_file="$state_dir/config.yml"

/bin/mkdir -p "$state_dir"

now_start="$(/bin/date +%H:%M)"
now_end="$(/bin/date -v+1H +%H:%M)"
future_start="$(/bin/date -v+2H +%H:%M)"
future_end="$(/bin/date -v+3H +%H:%M)"

cat <<EOF > "$config_file"
start_time: "$now_start"
end_time: "$now_end"
prewarn_minutes: 5
prewarn_title: ""
prewarn_message: "Test"
wallpaper_path: "/tmp/does-not-exist.png"
hardstop_action: "lock"
lock_interval_seconds: 60
show_idle: false
EOF

echo "Test: dry-run kickout during quiet hours"
HARDSTOP_DRY_RUN=1 HARDSTOP_STATE_DIR="$state_dir" HARDSTOP_CONFIG="$config_file" \
  "$repo_root/scripts/hardstop-kickout.sh"

if [ ! -f "$state_dir/last_lock_epoch.txt" ]; then
  echo "FAIL: last_lock_epoch.txt not created"
  exit 1
fi

echo "Test: SwiftBar plugin output during quiet hours"
out="$(HARDSTOP_STATE_DIR="$state_dir" HARDSTOP_CONFIG="$config_file" \
  "$repo_root/swiftbar/hardstop.1s.sh")"
if ! /usr/bin/printf "%s" "$out" | /usr/bin/grep -q "🔒"; then
  echo "FAIL: expected lock icon during quiet hours"
  exit 1
fi

cat <<EOF > "$config_file"
start_time: "$future_start"
end_time: "$future_end"
prewarn_minutes: 5
prewarn_title: ""
prewarn_message: "Test"
wallpaper_path: "/tmp/does-not-exist.png"
hardstop_action: "lock"
lock_interval_seconds: 60
show_idle: false
EOF

echo "Test: SwiftBar hidden during open hours"
out="$(HARDSTOP_STATE_DIR="$state_dir" HARDSTOP_CONFIG="$config_file" \
  "$repo_root/swiftbar/hardstop.1s.sh")"
if [ -n "$out" ]; then
  echo "FAIL: expected empty output during open hours"
  exit 1
fi

cat <<EOF > "$config_file"
start_time: "$future_start"
end_time: "$future_end"
prewarn_minutes: 5
prewarn_title: ""
prewarn_message: "Test"
wallpaper_path: "/tmp/does-not-exist.png"
hardstop_action: "lock"
lock_interval_seconds: 60
show_idle: true
EOF

echo "Test: SwiftBar shows idle indicator when enabled"
out="$(HARDSTOP_STATE_DIR="$state_dir" HARDSTOP_CONFIG="$config_file" \
  "$repo_root/swiftbar/hardstop.1s.sh")"
if [ -z "$out" ]; then
  echo "FAIL: expected output when show_idle is true"
  exit 1
fi

echo "PASS: all tests"
