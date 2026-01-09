#!/bin/bash
set -euo pipefail

# --- Configuration ---
# 24-hour time, local machine time zone.
START_TIME="22:00"
END_TIME="09:00"

# Set this to a specific image you want as your nighttime reminder.
# Example: $HOME/hardstop.png
WALLPAPER_PATH="$HOME/hardstop.png"

# Minutes before START_TIME to show a reminder.
PREWARN_MINUTES=5

PREWARN_TITLE=""
PREWARN_MESSAGE="Wrap up now and write your log-off ritual for tomorrow."

# Action when quiet hours start: "lock" or "logout".
HARDSTOP_ACTION="lock"

# Fast test settings (seconds).
TEST_FAST_INTERVAL_SECONDS=10
TEST_FAST_DURATION_SECONDS=40
TEST_FAST_PREWARN_SECONDS=10

STATE_DIR="${HARDSTOP_STATE_DIR:-$HOME/Library/Application Support/hardstop}"
REPO_FILE="$HOME/.local/share/hardstop/repo_path"
CONFIG_FILE=""
DRY_RUN="${HARDSTOP_DRY_RUN:-0}"
WALLPAPER_STATE_FILE="$STATE_DIR/wallpaper_before.txt"
WALLPAPER_STORE="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
WALLPAPER_STORE_BACKUP="$STATE_DIR/Index.plist.backup"
WALLPAPER_PREFS="$HOME/Library/Preferences/com.apple.wallpaper.plist"
WALLPAPER_PREFS_BACKUP="$STATE_DIR/com.apple.wallpaper.plist.backup"
LAST_LOCK_FILE="$STATE_DIR/last_lock_epoch.txt"
ACTIVE_FILE="$STATE_DIR/active"
WARN_FILE_PREFIX="$STATE_DIR/warned_"

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

# Allow optional per-user overrides without editing this script.
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

expand_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  echo "$p"
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

  val="$(yaml_get prewarn_minutes)"
  if /usr/bin/printf "%s" "$val" | /usr/bin/grep -Eq '^[0-9]+$'; then
    PREWARN_MINUTES="$val"
  fi

  val="$(yaml_get prewarn_title)"
  if [ -n "$val" ]; then
    PREWARN_TITLE="$val"
  fi

  val="$(yaml_get prewarn_message)"
  if [ -n "$val" ]; then
    PREWARN_MESSAGE="$val"
  fi

  val="$(yaml_get wallpaper_path)"
  if [ -n "$val" ]; then
    WALLPAPER_PATH="$(expand_path "$val")"
  fi

  val="$(yaml_get hardstop_action)"
  if [ "$val" = "lock" ] || [ "$val" = "logout" ]; then
    HARDSTOP_ACTION="$val"
  fi
}

apply_yaml_overrides

to_minutes() {
  local t="$1"
  local h="${t%:*}"
  local m="${t#*:}"
  echo "$((10#$h * 60 + 10#$m))"
}

ensure_state_dir() {
  /bin/mkdir -p "$STATE_DIR"
}

minutes_until_start() {
  local start now
  start="$(to_minutes "$START_TIME")"
  now="$(to_minutes "$(/bin/date +%H:%M)")"

  if [ "$now" -le "$start" ]; then
    echo "$((start - now))"
  else
    echo "$((24 * 60 - now + start))"
  fi
}

next_start_stamp() {
  local start now
  start="$(to_minutes "$START_TIME")"
  now="$(to_minutes "$(/bin/date +%H:%M)")"

  if [ "$now" -le "$start" ]; then
    /bin/date +%Y%m%d
  else
    /bin/date -v+1d +%Y%m%d
  fi
}

in_quiet_hours() {
  local start end now
  start="$(to_minutes "$START_TIME")"
  end="$(to_minutes "$END_TIME")"
  now="$(to_minutes "$(/bin/date +%H:%M)")"

  if [ "$start" -lt "$end" ]; then
    [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]
  else
    [ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
  fi
}

send_prewarn() {
  local mode until stamp warn_file title message
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  mode="${1:-}"
  if [ "$PREWARN_MINUTES" -le 0 ]; then
    return 0
  fi

  if [ "$mode" = "force" ]; then
    until="$PREWARN_MINUTES"
  else
    until="$(minutes_until_start)"
  fi

  if [ "$mode" = "force" ] || { [ "$until" -le "$PREWARN_MINUTES" ] && [ "$until" -gt 0 ]; }; then
    if [ "$mode" != "force" ]; then
      stamp="$(next_start_stamp)"
      warn_file="${WARN_FILE_PREFIX}${stamp}"
      if [ -f "$warn_file" ]; then
        return 0
      fi
    fi

    title="$PREWARN_TITLE"
    message="$PREWARN_MESSAGE"
    if [ -z "$title" ]; then
      title="Hard stop in ${until} minutes"
    fi
    if [ -z "$message" ]; then
      message="Wrap up now and write your log-off ritual for tomorrow."
    fi

    /usr/bin/osascript <<APPLESCRIPT
display dialog "${message}" with title "${title}" buttons {"OK"} default button 1 with icon caution
APPLESCRIPT
    if [ "$mode" != "force" ]; then
      /usr/bin/touch "$warn_file"
    fi
  fi
}

save_wallpaper_state() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ -f "$WALLPAPER_STATE_FILE" ]; then
    return 0
  fi

  if [ -f "$WALLPAPER_STORE" ] && [ ! -f "$WALLPAPER_STORE_BACKUP" ]; then
    /bin/cp "$WALLPAPER_STORE" "$WALLPAPER_STORE_BACKUP"
  fi
  if [ -f "$WALLPAPER_PREFS" ] && [ ! -f "$WALLPAPER_PREFS_BACKUP" ]; then
    /bin/cp "$WALLPAPER_PREFS" "$WALLPAPER_PREFS_BACKUP"
  fi

  /usr/bin/osascript <<APPLESCRIPT > "$WALLPAPER_STATE_FILE"
tell application "System Events"
  set picList to {}
  repeat with d in desktops
    try
      set end of picList to (POSIX path of (picture of d as alias))
    on error
      set end of picList to "<missing>"
    end try
  end repeat
end tell
set text item delimiters to "\n"
return picList as text
APPLESCRIPT
}

set_wallpaper() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ ! -f "$WALLPAPER_PATH" ]; then
    return 0
  fi

  save_wallpaper_state || true
  /usr/bin/osascript <<APPLESCRIPT || true
set picturePath to POSIX file "${WALLPAPER_PATH}"
tell application "System Events"
  repeat with d in desktops
    set picture of d to picturePath
  end repeat
end tell
APPLESCRIPT

  /usr/bin/touch "$ACTIVE_FILE" || true
}

restore_wallpaper_store() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ -f "$WALLPAPER_PREFS_BACKUP" ]; then
    /bin/cp "$WALLPAPER_PREFS_BACKUP" "$WALLPAPER_PREFS"
  fi

  if [ -f "$WALLPAPER_STORE_BACKUP" ]; then
    /bin/cp "$WALLPAPER_STORE_BACKUP" "$WALLPAPER_STORE"
    /usr/bin/killall WallpaperAgent >/dev/null 2>&1 || true
  fi
}

print_current_wallpaper() {
  /usr/bin/osascript <<APPLESCRIPT
tell application "System Events"
  set picList to {}
  repeat with d in desktops
    try
      set end of picList to (POSIX path of (picture of d as alias))
    on error
      set end of picList to "<missing>"
    end try
  end repeat
end tell
set text item delimiters to "\n"
return picList as text
APPLESCRIPT
}

print_wallpaper_provider() {
  if [ ! -f "$WALLPAPER_STORE" ]; then
    return 0
  fi

  /usr/bin/python3 - <<PY
import os, plistlib
path = os.path.expanduser("$WALLPAPER_STORE")
with open(path, "rb") as f:
    data = plistlib.load(f)

def get_provider(root):
    displays = root.get("Displays", {})
    if displays:
        first = next(iter(displays.values()))
        choices = first.get("Desktop", {}).get("Content", {}).get("Choices", [])
        if choices:
            return choices[0].get("Provider")
    choices = root.get("AllSpacesAndDisplays", {}).get("Desktop", {}).get("Content", {}).get("Choices", [])
    if choices:
        return choices[0].get("Provider")
    return None

provider = get_provider(data)
if provider:
    print(provider)
PY
}

print_system_wallpaper_url() {
  if [ ! -f "$WALLPAPER_PREFS" ]; then
    return 0
  fi

  /usr/bin/plutil -p "$WALLPAPER_PREFS" | /usr/bin/awk -F'"' '/SystemWallpaperURL/ {print $4; exit}'
}

restore_wallpaper() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if [ ! -f "$ACTIVE_FILE" ]; then
    return 0
  fi

  if [ -s "$WALLPAPER_STATE_FILE" ]; then
    if /usr/bin/grep -qv -e '^$' -e '^<missing>$' "$WALLPAPER_STATE_FILE"; then
      /usr/bin/osascript <<APPLESCRIPT || true
set stateFile to POSIX file "${WALLPAPER_STATE_FILE}"
set picList to paragraphs of (read stateFile)
tell application "System Events"
  set deskList to desktops
  set deskCount to count of deskList
  repeat with i from 1 to deskCount
    if i is greater than (count of picList) then exit repeat
    set p to item i of picList
    if p is not "" and p is not "<missing>" then
      try
        set picture of item i of deskList to POSIX file p
      end try
    end if
  end repeat
end tell
APPLESCRIPT
    else
      restore_wallpaper_store || true
    fi
  else
    restore_wallpaper_store || true
  fi

  /bin/rm -f "$ACTIVE_FILE" "$WALLPAPER_STATE_FILE" "$WALLPAPER_STORE_BACKUP" "$WALLPAPER_PREFS_BACKUP" || true
}

logout_user() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  /usr/bin/osascript -e 'tell application "System Events" to log out'
}

lock_screen() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  local cgsession
  cgsession="/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

  if [ -x "$cgsession" ]; then
    "$cgsession" -suspend
    return 0
  fi

  if ! /usr/bin/osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}'; then
    /usr/bin/pmset displaysleepnow
  fi
}

apply_action() {
  /bin/date +%s > "$LAST_LOCK_FILE"
  if [ "$HARDSTOP_ACTION" = "logout" ]; then
    logout_user
  else
    lock_screen
  fi
}

run_test_fast() {
  local interval duration prewarn end
  interval="$TEST_FAST_INTERVAL_SECONDS"
  duration="$TEST_FAST_DURATION_SECONDS"
  prewarn="$TEST_FAST_PREWARN_SECONDS"

  if [ "$prewarn" -gt 0 ]; then
    /usr/bin/osascript <<APPLESCRIPT
display dialog "Test mode: hard stop in ${prewarn} seconds." with title "Hard stop test" buttons {"OK"} default button 1 with icon caution
APPLESCRIPT
    /bin/sleep "$prewarn"
  fi

  set_wallpaper

  end=$((SECONDS + duration))
  while [ "$SECONDS" -lt "$end" ]; do
    apply_action
    /bin/sleep "$interval"
  done

  restore_wallpaper
  /bin/rm -f "$LAST_LOCK_FILE"
  /usr/bin/osascript -e 'display notification "Test complete. Restored wallpaper." with title "Hard stop test"'
}

main() {
  ensure_state_dir

  if [ "${1:-}" = "--test" ]; then
    /usr/bin/osascript -e "display notification \"Test mode: showing reminder + wallpaper only.\" with title \"Hard stop test\""
    send_prewarn force
    set_wallpaper
    exit 0
  fi

  if [ "${1:-}" = "--test-lock" ]; then
    /usr/bin/osascript -e "display notification \"Test mode: locking screen now.\" with title \"Hard stop test\""
    send_prewarn force
    set_wallpaper
    lock_screen
    exit 0
  fi

  if [ "${1:-}" = "--test-logout" ]; then
    /usr/bin/osascript -e "display notification \"Test mode: logging out now.\" with title \"Hard stop test\""
    send_prewarn force
    set_wallpaper
    logout_user
    exit 0
  fi

  if [ "${1:-}" = "--test-fast" ]; then
    run_test_fast
    exit 0
  fi

  if [ "${1:-}" = "--restore" ]; then
    restore_wallpaper
    exit 0
  fi

  if [ "${1:-}" = "--print-wallpaper" ]; then
    print_current_wallpaper
    exit 0
  fi

  if [ "${1:-}" = "--print-wallpaper-provider" ]; then
    print_wallpaper_provider
    exit 0
  fi

  if [ "${1:-}" = "--print-system-wallpaper-url" ]; then
    print_system_wallpaper_url
    exit 0
  fi

  if ! in_quiet_hours; then
    restore_wallpaper
    send_prewarn
    /bin/rm -f "$LAST_LOCK_FILE"
    exit 0
  fi

  set_wallpaper
  apply_action
}

main "$@"
