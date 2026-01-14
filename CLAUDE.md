# CLAUDE.md

Project context for Claude Code.

## What This Is

Hard Stop is a macOS tool that enforces computer shutdown during "quiet hours" (9 PM - 8 AM by default). It uses `sudo shutdown -h now` to force shutdown, and if the computer is turned back on during quiet hours, it will shut down again every 5 minutes.

## Architecture

- **LaunchAgent** (`launchd/com.hardstop.kickout.plist`): macOS service that runs the script every 5 minutes
- **Main script** (`scripts/hardstop-kickout.sh`): Checks if current time is in quiet hours, runs shutdown if so
- **CLI wrapper** (`scripts/hardstop`): User-facing commands (enable, disable, status, etc.)
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

**Temporarily disable**: `hardstop disable`

**Test without shutdown**: `hardstop test`

**Check status**: `hardstop status`

**Run test suite**: `bash scripts/test.sh`

## Test Suite

The test suite (`scripts/test.sh`) verifies:
- File existence and syntax
- Config parsing
- Plist validation (on macOS)
- Time logic unit tests (14 test cases)
- Installation status
- LaunchAgent status

All unit tests are safe - no actual shutdowns occur.

## Live Integration Test

To test the actual shutdown mechanism:

```bash
hardstop test-live              # 3 min test, shutdown every 60s
hardstop test-live 300 30       # 5 min test, shutdown every 30s
hardstop test-live-cancel       # Cancel early
```

This creates a `test_live_until` file with an expiration timestamp. The script checks this file and shuts down regardless of quiet hours until it expires.
