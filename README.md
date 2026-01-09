# Hard Stop (Simple Kickout)

This setup locks the screen every minute during quiet hours (default 22:00–09:00)
and sets a reminder wallpaper if the image exists. (You can switch to full
logout via `HARDSTOP_ACTION`.)

## Files
- `scripts/hardstop-kickout.sh` — the enforcement script
- `launchd/com.hardstop.kickout.plist` — LaunchAgent, runs every 60 seconds
- `FUTURE_PLAN.md` — a harder combined plan for later

## Setup
1) Pick or create a reminder image and save it somewhere stable, for example:
   `~/hardstop.png`

2) Edit the config at the top of `scripts/hardstop-kickout.sh`:
   - `START_TIME` (default `22:00`)
   - `END_TIME` (default `09:00`)
   - `WALLPAPER_PATH` (path to your reminder image, default `~/hardstop.png`)
   - `PREWARN_MINUTES` (default `5`)
   - `PREWARN_TITLE` / `PREWARN_MESSAGE` (title auto-fills if empty)
   - `HARDSTOP_ACTION` (`lock` for lock screen, `logout` to fully log out)

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
- Future idea: add a SwiftBar menu bar countdown for the last 5 minutes before
  hard stop.
- Locking uses `CGSession` if available; otherwise it sends the
  Control+Command+Q keystroke and may require Accessibility permission for
  Terminal or `osascript`.

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
