#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="$HOME/.local/share/hardstop"
repo_file="$state_dir/repo_path"

src_script="$repo_root/scripts/hardstop-kickout.sh"
src_wrapper="$repo_root/scripts/hardstop"
src_plist="$repo_root/launchd/com.hardstop.kickout.plist"
src_sudoers="$repo_root/sudoers/hardstop-shutdown"

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
repo_config="$repo_root/config.yml"

echo "=== Hard Stop Installer ==="
echo ""
echo "This will install a hard shutdown enforcer that:"
echo "  - Shuts down your computer at 9 PM"
echo "  - Keeps shutting down every 5 minutes if you turn it back on"
echo "  - Stops enforcing at 8 AM"
echo ""

# Create directories
/bin/mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
/bin/mkdir -p "$state_dir"

install_exec() {
  local src="$1"
  local dest="$2"
  local tmp
  tmp="$(/usr/bin/mktemp "${dest}.tmp.XXXXXX")"
  /bin/cp "$src" "$tmp"
  /bin/chmod +x "$tmp"
  /bin/mv "$tmp" "$dest"
}

# Install scripts
install_exec "$src_script" "$dest_bin"
install_exec "$src_wrapper" "$dest_wrapper"

# Get interval from config
existing_interval=""
if [ -f "$dest_plist" ]; then
  existing_interval="$(/usr/bin/plutil -p "$dest_plist" | /usr/bin/awk '/StartInterval/ {print $3; exit}')"
fi

/bin/cp "$src_plist" "$dest_plist"

cfg_source="$repo_config"
yaml_interval="$(/usr/bin/awk -F: '/^[[:space:]]*lock_interval_seconds[[:space:]]*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"/, "", $2); gsub(/"$/, "", $2); print $2; exit}' "$cfg_source" 2>/dev/null || echo "")"
if /usr/bin/printf "%s" "$yaml_interval" | /usr/bin/grep -Eq '^[0-9]+$'; then
  /usr/bin/plutil -replace StartInterval -integer "$yaml_interval" "$dest_plist"
elif [ -n "$existing_interval" ]; then
  /usr/bin/plutil -replace StartInterval -integer "$existing_interval" "$dest_plist"
fi

# Install LaunchAgent
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$dest_plist" >/dev/null 2>&1 || true
/bin/launchctl enable "gui/$(/usr/bin/id -u)/com.hardstop.kickout" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$dest_plist"

# Store repo path
/usr/bin/printf "%s\n" "$repo_root" > "$repo_file"

echo ""
echo "Scripts installed:"
echo "  - $dest_bin"
echo "  - $dest_wrapper"
echo "  - $dest_plist"
echo ""

# Install sudoers file for passwordless shutdown
echo "=== Sudoers Configuration ==="
echo ""
echo "To allow shutdown without password prompts, we need to install a sudoers rule."
echo "This requires your password (one time only)."
echo ""

dest_sudoers="/etc/sudoers.d/hardstop-shutdown"

if [ -f "$dest_sudoers" ]; then
  echo "Sudoers file already installed at $dest_sudoers"
else
  echo "Installing sudoers rule to allow passwordless shutdown..."
  if /usr/bin/sudo /bin/cp "$src_sudoers" "$dest_sudoers" && \
     /usr/bin/sudo /bin/chmod 440 "$dest_sudoers" && \
     /usr/bin/sudo /usr/bin/chown root:wheel "$dest_sudoers"; then
    echo "Sudoers file installed successfully."
  else
    echo ""
    echo "WARNING: Could not install sudoers file automatically."
    echo "You can install it manually with:"
    echo "  sudo cp $src_sudoers /etc/sudoers.d/hardstop-shutdown"
    echo "  sudo chmod 440 /etc/sudoers.d/hardstop-shutdown"
    echo "  sudo chown root:wheel /etc/sudoers.d/hardstop-shutdown"
  fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Hard stop is now active!"
echo "  - Quiet hours: 9 PM - 8 AM"
echo "  - Check interval: 5 minutes"
echo ""
echo "Commands:"
echo "  hardstop status   - Check if in quiet hours"
echo "  hardstop test     - Test without actually shutting down"
echo "  hardstop config   - Edit quiet hours settings"
echo ""
