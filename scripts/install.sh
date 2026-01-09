#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="$HOME/.local/share/hardstop"
repo_file="$state_dir/repo_path"

src_script="$repo_root/scripts/hardstop-kickout.sh"
src_wrapper="$repo_root/scripts/hardstop"
src_plist="$repo_root/launchd/com.hardstop.kickout.plist"
src_plugin="$repo_root/swiftbar/hardstop.1s.sh"

if [ ! -f "$src_script" ]; then
  echo "Missing $src_script" >&2
  exit 1
fi

if [ ! -f "$src_plist" ]; then
  echo "Missing $src_plist" >&2
  exit 1
fi

if [ ! -f "$src_wrapper" ]; then
  echo "Missing $src_wrapper" >&2
  exit 1
fi

dest_bin="$HOME/.local/bin/hardstop-kickout.sh"
dest_wrapper="$HOME/.local/bin/hardstop"
dest_plist="$HOME/Library/LaunchAgents/com.hardstop.kickout.plist"
plugin_dir="$HOME/Library/Application Support/SwiftBar/Plugins"
plugin_dest="$plugin_dir/hardstop.1s.sh"
plugin_old="$plugin_dir/hardstop.10s.sh"
config_file="$HOME/Library/Application Support/hardstop/config.yml"
repo_config="$repo_root/config.yml"

/bin/mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
/bin/mkdir -p "$state_dir"
/bin/mkdir -p "$(dirname "$config_file")"
if [ ! -f "$config_file" ] && [ ! -f "$repo_config" ]; then
  cat <<'EOF' > "$repo_config"
# Hardstop config (YAML, flat keys)
start_time: "22:00"
end_time: "09:00"
prewarn_minutes: 5
prewarn_title: ""
prewarn_message: "Wrap up now and write your log-off ritual for tomorrow."
wallpaper_path: "$HOME/hardstop.png"
hardstop_action: "lock"
lock_interval_seconds: 60
show_idle: false
EOF
fi

install_exec() {
  local src="$1"
  local dest="$2"
  local tmp
  tmp="$(/usr/bin/mktemp "${dest}.tmp.XXXXXX")"
  /bin/cp "$src" "$tmp"
  /bin/chmod +x "$tmp"
  /bin/mv "$tmp" "$dest"
}

install_exec "$src_script" "$dest_bin"
install_exec "$src_wrapper" "$dest_wrapper"
install_exec "$repo_root/scripts/test.sh" "$HOME/.local/bin/hardstop-test.sh"

/bin/mkdir -p "$plugin_dir"
if [ -f "$src_plugin" ]; then
  /bin/rm -f "$plugin_old"
  install_exec "$src_plugin" "$plugin_dest"
fi

existing_interval=""
if [ -f "$dest_plist" ]; then
  existing_interval="$(/usr/bin/plutil -p "$dest_plist" | /usr/bin/awk '/StartInterval/ {print $3; exit}')"
fi

/bin/cp "$src_plist" "$dest_plist"

cfg_source="$config_file"
if [ -f "$repo_config" ]; then
  cfg_source="$repo_config"
fi
yaml_interval="$(/usr/bin/awk -F: '/^[[:space:]]*lock_interval_seconds[[:space:]]*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"/, "", $2); gsub(/"$/, "", $2); print $2; exit}' "$cfg_source")"
if /usr/bin/printf "%s" "$yaml_interval" | /usr/bin/grep -Eq '^[0-9]+$'; then
  /usr/bin/plutil -replace StartInterval -integer "$yaml_interval" "$dest_plist"
elif [ -n "$existing_interval" ]; then
  /usr/bin/plutil -replace StartInterval -integer "$existing_interval" "$dest_plist"
fi

/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$dest_plist" >/dev/null 2>&1 || true
/bin/launchctl enable "gui/$(/usr/bin/id -u)/com.hardstop.kickout" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$dest_plist"

/usr/bin/printf "%s\n" "$repo_root" > "$repo_file"

cat <<MSG
Installed hard stop kickout:
- Script: $dest_bin
- Command: $dest_wrapper
- LaunchAgent: $dest_plist

If this is the first run, macOS may prompt for Automation permissions.
MSG
