# Future Plan: Launchd Logout + Wi-Fi Off + PF Firewall

## Goal
Create a hard nightly cutoff that logs you out, disables Wi-Fi, and blocks outbound traffic while still allowing a manual emergency override.

## Outline
1) Define policy
- Start time (e.g., 22:00) and end time (e.g., 06:00)
- Emergency override method (local admin command)
- Decide whether to include a pre-warning notification

2) Enforcer script (root)
- Disable Wi-Fi: `networksetup -setairportpower <device> off`
- Enable pf and load a custom anchor that blocks outbound traffic
- Log out active GUI users (e.g., `launchctl bootout gui/<uid>`)

3) PF anchor and config
- Create `/etc/pf.anchors/hardstop` with outbound block rules
- Add an anchor entry in `/etc/pf.conf`
- Validate with `pfctl -nf /etc/pf.conf`

4) LaunchDaemons
- `/Library/LaunchDaemons/com.hardstop.enforce.plist` at 22:00
- `/Library/LaunchDaemons/com.hardstop.restore.plist` at 06:00
- Both run the enforcer script with different arguments

5) Restore script (root)
- Disable pf rules or unload anchor
- Re-enable Wi-Fi
- Optional: reset wallpaper or notify

6) Emergency override
- One command that disables pf, re-enables Wi-Fi, and unloads the LaunchDaemons
- Store the command in a local note and optionally on paper

7) Test plan
- Dry run: `pfctl -s rules` and `networksetup -getairportpower`
- Confirm logout behavior and restore behavior
- Test emergency override

## Risks to manage
- Incorrect pf config can block network until restored
- Running as root requires careful file paths and permissions
- If you rely on remote access at night, this will cut it off
