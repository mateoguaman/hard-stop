# Hard Stop

A simple, aggressive computer shutdown enforcer for macOS. During quiet hours (default 9 PM - 8 AM), your computer will shut down. If you turn it back on, it will shut down again every 5 minutes until quiet hours end.

No warnings. No dialogs. Just shutdown.

## How It Works

1. A **macOS LaunchAgent** runs the script every 5 minutes (configurable)
2. If the current time is within quiet hours, it runs `sudo shutdown -h now`
3. If you turn your computer back on during quiet hours, you get a **grace period** (default 5 minutes) before it shuts down again
4. This continues until 8 AM when quiet hours end

**Note on timing**: The first shutdown happens at the first 5-minute interval check after 9 PM (not exactly at 9:00 PM). Worst case is ~5 minutes after 9 PM.

### Why LaunchAgent (not cron)?

This uses macOS's native `launchd` system instead of cron:
- LaunchAgents are user-session aware (only run when logged in)
- Managed via `launchctl` commands
- The plist file defines the schedule (`StartInterval: 300` = every 300 seconds)

## Files

- `scripts/hardstop-kickout.sh` - the enforcement script (checks time, shuts down)
- `scripts/hardstop` - CLI wrapper for managing the service
- `scripts/install.sh` - installer
- `scripts/test.sh` - test suite (safe, no actual shutdowns)
- `launchd/com.hardstop.kickout.plist` - LaunchAgent configuration
- `sudoers/hardstop-shutdown` - sudoers rule for passwordless shutdown
- `config.yml` - configuration (times, interval)

## Installation

```bash
bash scripts/install.sh
```

The installer will:
1. Copy scripts to `~/.local/bin/`
2. Install the LaunchAgent
3. Install a sudoers rule (requires your password once) to allow shutdown without prompts

## Configuration

Edit `config.yml`:

```yaml
start_time: "21:00"              # 9 PM - quiet hours start
end_time: "08:00"                # 8 AM - quiet hours end
lock_interval_seconds: 300       # 5 minutes - check/shutdown interval
```

After editing, reload:
```bash
hardstop reload
```

## Commands

```bash
hardstop status    # Check if in quiet hours, grace period, and service status
hardstop check     # Dry-run: show what would happen (no actual shutdown)
hardstop test      # Run the test suite (no actual shutdowns)
hardstop disable   # Temporarily disable enforcement
hardstop enable    # Re-enable enforcement
hardstop reload    # Reload after config changes
hardstop config    # Edit configuration file
hardstop install   # Re-install from repo
```

If `hardstop` is not found, add `~/.local/bin` to your PATH or use:
```bash
~/.local/bin/hardstop <command>
```

## Sudoers Setup

The installer automatically installs a sudoers rule to `/etc/sudoers.d/hardstop-shutdown` that allows the `shutdown` command to run without a password prompt.

If you need to install it manually:
```bash
sudo cp sudoers/hardstop-shutdown /etc/sudoers.d/hardstop-shutdown
sudo chmod 440 /etc/sudoers.d/hardstop-shutdown
sudo chown root:wheel /etc/sudoers.d/hardstop-shutdown
```

## Disable

Temporarily:
```bash
hardstop disable
```

Permanently (remove everything):
```bash
hardstop disable
rm ~/.local/bin/hardstop*
rm ~/Library/LaunchAgents/com.hardstop.kickout.plist
sudo rm /etc/sudoers.d/hardstop-shutdown
```

## Testing

### Safe tests (no shutdown)

```bash
hardstop test             # Run the full test suite (38 tests)
hardstop check            # Dry-run: show quiet hours status, grace period, etc.
```

### Live integration test (WILL shutdown!)

To verify the full shutdown mechanism works:

```bash
hardstop test-live              # 3 min test, 60s interval/grace period
hardstop test-live 300 30       # 5 min test, 30s interval/grace period
```

This will:
1. **Immediately shutdown** your computer
2. When you turn it back on, you get a **grace period** equal to the interval (e.g., 60s)
3. After the grace period, shutdown again
4. After 3 minutes (or custom duration), test mode auto-expires
5. System returns to normal operation (grace period returns to 5 min from config)

**To cancel early** (you have the grace period to do this after rebooting):
```bash
hardstop test-live-cancel
```

### Unit test suite

Run with `hardstop test`. The test suite checks:
- All required files exist
- Script syntax is valid
- Config file parses correctly
- Time logic works (14 unit tests for quiet hours detection)
- Installation paths are correct
- LaunchAgent is loaded (on macOS)
- Sudoers permissions

All 38 tests are safe - no actual shutdowns will occur.

## Grace Period

When you reboot during quiet hours, you get a **grace period** before the next shutdown. This allows you to:
- Quickly do something urgent on your computer
- Run `hardstop disable` if you need to work late

The grace period equals `lock_interval_seconds` from config (default 5 minutes). During `test-live` mode, the grace period equals the test interval instead.

## Troubleshooting

**Shutdown doesn't happen?**
- Check if the service is enabled: `hardstop status`
- Test the time logic: `hardstop check`
- Verify sudoers is installed: `sudo -n /sbin/shutdown -h now` (should not prompt for password)

**Want to change the times?**
- Edit `config.yml` and run `hardstop reload`

**Need to escape quiet hours?**
- You have a 5-minute grace period after each boot - run `hardstop disable` during that window
