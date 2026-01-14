# Hard Stop

A simple, aggressive computer shutdown enforcer for macOS. During quiet hours (default 9 PM - 8 AM), your computer will shut down. If you turn it back on, it will shut down again every 5 minutes until quiet hours end.

No warnings. No dialogs. Just shutdown.

## How It Works

1. A LaunchAgent runs every 5 minutes (configurable)
2. If the current time is within quiet hours, it runs `sudo shutdown -h now`
3. If you turn your computer back on during quiet hours, it will shut down again
4. This continues until 8 AM when quiet hours end

## Files

- `scripts/hardstop-kickout.sh` - the enforcement script (checks time, shuts down)
- `scripts/hardstop` - CLI wrapper for managing the service
- `scripts/install.sh` - installer
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
hardstop status    # Check if in quiet hours and if service is enabled
hardstop test      # Test without actually shutting down
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

## Troubleshooting

**Shutdown doesn't happen?**
- Check if the service is enabled: `hardstop status`
- Test the time logic: `hardstop test`
- Verify sudoers is installed: `sudo -n /sbin/shutdown -h now` (should not prompt for password)

**Want to change the times?**
- Edit `config.yml` and run `hardstop reload`

**Need to escape quiet hours?**
- Run `hardstop disable` quickly after booting, before the 5-minute check runs
