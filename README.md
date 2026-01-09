# Hard Stop (Simple Kickout)

This setup locks the screen every minute during quiet hours (default 22:00–09:00)
and sets a reminder wallpaper if the image exists. (You can switch to full
logout via `HARDSTOP_ACTION`.)

## Files
- `scripts/hardstop-kickout.sh` — the enforcement script
- `scripts/hardstop` — CLI wrapper (enable/disable/test/config)
- `scripts/install.sh` — installer
- `scripts/test.sh` — dry-run test suite
- `launchd/com.hardstop.kickout.plist` — LaunchAgent, runs every 60 seconds
- `swiftbar/hardstop.1s.sh` — SwiftBar menu bar plugin
- `config.yml` — editable config (preferred)
- `FUTURE_PLAN.md` — a harder combined plan for later

## Setup
1) Pick or create a reminder image and save it somewhere stable, for example:
   `~/hardstop.png`

2) Edit the YAML config (recommended, stored in the repo):
```bash
hardstop config
```

Config file location (preferred): `config.yml` at the repo root.
Fallback location: `~/Library/Application Support/hardstop/config.yml`
Editor: uses `vim` by default; override with `HARDSTOP_EDITOR` or `$EDITOR`.

Key settings:
- `start_time` / `end_time` (e.g., `"22:00"` / `"09:00"`)
- `prewarn_minutes`
- `prewarn_title` / `prewarn_message`
- `wallpaper_path`
- `hardstop_action` (`lock` or `logout`)
- `lock_interval_seconds`
- `show_idle` (SwiftBar: show or hide during open hours)

3) Install the script and LaunchAgent:
```bash
mkdir -p ~/.local/bin
cp scripts/hardstop-kickout.sh ~/.local/bin/
chmod +x ~/.local/bin/hardstop-kickout.sh

cp scripts/hardstop ~/.local/bin/
chmod +x ~/.local/bin/hardstop

mkdir -p ~/Library/LaunchAgents
cp launchd/com.hardstop.kickout.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.hardstop.kickout.plist
```

Or run the installer (no chmod needed):
```bash
bash scripts/install.sh
```

## Commands (recommended)
After install, use the `hardstop` command:
```bash
hardstop install
hardstop install-swiftbar
hardstop config
hardstop interval 60
hardstop enable
hardstop disable
hardstop reload
hardstop status
hardstop test
hardstop test-fast
hardstop test-lock
hardstop test-logout
hardstop restore
hardstop wallpaper
```

If `hardstop` is not found, add `~/.local/bin` to your PATH or use:
```bash
~/.local/bin/hardstop <command>
```

## Notes
- The script only runs when you are logged in.
- The first time it runs, macOS will likely ask for permission to allow
  `osascript` to control "System Events" (logout and wallpaper change).
  If you do not see a prompt, run the script manually once from Terminal.
- The script stores your previous wallpapers in
  `~/Library/Application Support/hardstop/wallpaper_before.txt` and restores
  them after quiet hours end.
- If you use dynamic wallpapers (Aerials, etc.), the script also snapshots
  `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` and
  restores it after quiet hours, along with `~/Library/Preferences/com.apple.wallpaper.plist`.
- Locking uses `CGSession` if available; otherwise it sends the
  Control+Command+Q keystroke and may require Accessibility permission for
  Terminal or `osascript`.
- SwiftBar plugin lives at `swiftbar/hardstop.1s.sh`. It refreshes every 1
  second and only shows during prewarn/quiet hours by default.
- If you change `lock_interval_seconds` manually, run `hardstop reload` (or
  `hardstop interval <seconds>`) to apply it to launchd.

## Test mode
Run these by hand to verify behavior without waiting until 10 pm (prewarn is forced):
```bash
~/.local/bin/hardstop-kickout.sh --test
~/.local/bin/hardstop-kickout.sh --test-fast
~/.local/bin/hardstop-kickout.sh --test-lock
~/.local/bin/hardstop-kickout.sh --test-logout
~/.local/bin/hardstop-kickout.sh --restore
~/.local/bin/hardstop-kickout.sh --print-wallpaper
```

## Test suite
Run a safe, dry-run test suite (no locks, no wallpaper changes):
```bash
hardstop-test.sh
```

## SwiftBar menu bar plugin
1) Install SwiftBar from https://swiftbar.app if you do not have it.
2) Run (also happens automatically during `hardstop install`):
```bash
hardstop install-swiftbar
```
3) In SwiftBar, make sure plugins are enabled and refresh if needed.

## Disable
```bash
hardstop disable
```

Or manually:
```bash
launchctl unload -w ~/Library/LaunchAgents/com.hardstop.kickout.plist
```

## Troubleshooting
- If wallpaper does not change, check the image path and file permissions.
- If logout does not happen, make sure Automation permissions are granted for
  `osascript` or Terminal in System Settings > Privacy & Security > Automation.
- If lock does not happen, grant Accessibility permission to Terminal (or
  `osascript`) so it can send Control+Command+Q.
- If it still does not lock, the wallpaper change can fail and exit early in
  some environments. The script now treats wallpaper changes as best-effort,
  so reinstall to pick up the fix.
- Dynamic wallpapers show `<missing>` in System Events; use `hardstop wallpaper`
  to confirm the provider and `SystemWallpaperURL`.
- If `launchctl load` fails with `Load failed: 5`, prefer `hardstop enable`
  (uses `launchctl bootstrap`).

## Wallpaper reset (CLI)
Reset Sonoma Horizon explicitly:
```bash
wallpaper="/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.mov"
osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$wallpaper\""
killall WallpaperAgent
```

## Field Notes (from setup)
- `defaults write com.apple.wallpaper SystemWallpaperURL ...` can be
  overwritten by the wallpaper store; using `osascript` to set the picture
  and restarting `WallpaperAgent` sticks.
- The wallpaper store may show both `aerials` and `image` providers; this is
  normal when Aerials is used for screen saver or idle.
- `CGSession` is not present on every macOS build; the lock fallback uses the
  Control+Command+Q keystroke.
