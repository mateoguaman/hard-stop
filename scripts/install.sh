#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="$HOME/.local/share/hardstop"
repo_file="$state_dir/repo_path"

src_script="$repo_root/scripts/hardstop-kickout.sh"
src_wrapper="$repo_root/scripts/hardstop"
src_plist="$repo_root/launchd/com.hardstop.kickout.plist"

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

/bin/mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
/bin/mkdir -p "$state_dir"

/bin/cp "$src_script" "$dest_bin"
/bin/chmod +x "$dest_bin"

/bin/cp "$src_wrapper" "$dest_wrapper"
/bin/chmod +x "$dest_wrapper"

/bin/cp "$src_plist" "$dest_plist"

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
