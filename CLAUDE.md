# CLAUDE.md

Project context for Claude Code.

## What This Is

Hard Stop is a macOS tool that enforces computer shutdown during "quiet hours" (9 PM - 8 AM by default). It uses `sudo shutdown -h now` to force shutdown. If the computer is turned back on during quiet hours, it gives a grace period (default 5 minutes), then shuts down again.

## Architecture

- **LaunchAgent** (`launchd/com.hardstop.kickout.plist`): macOS service that runs the script every 5 minutes
- **Main script** (`scripts/hardstop-kickout.sh`): Checks if current time is in quiet hours, runs shutdown if so
- **CLI wrapper** (`scripts/hardstop`): User-facing commands (status, config, check, etc.)
- **Sudoers rule** (`sudoers/hardstop-shutdown`): Allows `shutdown` to run without password prompt
- **Config** (`config.yml`): User-editable settings (times, interval)

## Key Files

| File | Purpose |
|------|---------|
| `scripts/hardstop-kickout.sh` | Core logic: time check + shutdown |
| `scripts/hardstop` | CLI wrapper for launchctl commands |
| `scripts/install.sh` | Installer (copies files, sets up launchd, installs sudoers) |
| `scripts/test.sh` | Test suite (safe, no actual shutdowns) |
| `launchd/com.hardstop.kickout.plist` | LaunchAgent config (runs every 300s) |
| `sudoers/hardstop-shutdown` | Passwordless sudo for /sbin/shutdown |
| `config.yml` | start_time, end_time, interval |

## How Scheduling Works

Uses macOS `launchd` (not cron):
- `StartInterval: 300` = run every 300 seconds (5 min)
- `RunAtLoad: true` = run immediately when service loads
- Managed via `launchctl bootstrap/bootout`

The script checks time on each run - it's not scheduled for exactly 9 PM, but runs on interval and checks if within quiet hours.

## Installation Paths

After install:
- Scripts: `~/.local/bin/hardstop*`
- LaunchAgent: `~/Library/LaunchAgents/com.hardstop.kickout.plist`
- Sudoers: `/etc/sudoers.d/hardstop-shutdown`
- State: `~/.local/share/hardstop/repo_path` (stores repo location)

## Common Tasks

**Change quiet hours**: Edit `config.yml`, run `hardstop reload`

**Dry-run check**: `hardstop check` (shows quiet hours status, grace period)

**Check status**: `hardstop status`

**Run test suite**: `hardstop test`

## Test Suite

Run with `hardstop test`. The test suite (`scripts/test.sh`) verifies:
- File existence and syntax
- Config parsing
- Plist validation (on macOS)
- Time logic unit tests (14 test cases)
- Installation status
- LaunchAgent status
- Sudoers permissions

All 38 unit tests are safe - no actual shutdowns occur.

## Live Integration Test

To test the actual shutdown mechanism:

```bash
hardstop test-live              # 3 min test, 60s interval/grace period
hardstop test-live 300 30       # 5 min test, 30s interval/grace period
hardstop test-live-cancel       # Cancel early
```

This creates:
- `test_live_until` file with an expiration timestamp
- `test_live_interval` file with the test interval (used as grace period)

During test-live mode, the grace period equals the test interval, so you can test the grace period behavior with shorter times.

## Grace Period

After booting during quiet hours (or test-live mode), the system waits for a grace period before shutting down. This allows quick emergency access.

- Default grace period: `lock_interval_seconds` from config (300s / 5 min)
- During test-live: uses the test interval instead (e.g., 60s)
- Check current status with `hardstop check` or `hardstop status`
