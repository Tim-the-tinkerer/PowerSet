# PowerSet

A simple macOS GUI for Apple’s `pmset` power-management tool.

**Version:** 1.0.1 — see [CHANGELOG.md](CHANGELOG.md).

## What it does

Wraps commands like:

```bash
sudo pmset repeat restart U 05:00:00
```

so you can set them from a window instead of Terminal.

### Schedule tab

- **Event type** — Restart, Shut Down, Sleep, Wake, Power On, Wake or Power On  
- **Weekdays** — MTWRFSU toggles (with Weekdays / Every day / Clear)  
- **Time** — hour & minute picker  
- Live **command preview** (`sudo pmset …`)  
- **Apply Schedule** — runs with admin rights (macOS password dialog)  
- **Cancel Schedule** — `sudo pmset repeat cancel`  
- Shows current schedule via `pmset -g sched`

### Settings tab

Edit common timers and flags (scope: All / Battery / AC):

| Setting | pmset key |
|---------|-----------|
| Display sleep | `displaysleep` |
| System sleep | `sleep` |
| Disk sleep | `disksleep` |
| Wake for network | `womp` |
| Power Nap | `powernap` |
| Auto-restart after power loss | `autorestart` |
| Keep awake for TTYs | `ttyskeepawake` |
| Proximity wake | `proximitywake` |
| TCP keepalive | `tcpkeepalive` |

Also: **Sleep Display Now** and **Sleep Mac Now** (no admin needed).

### Status tab

Read-only dump of `pmset -g` and `pmset -g sched`.

## Requirements

- macOS 13 or later  
- Swift toolchain (Xcode or Command Line Tools)  
- Admin password when applying changes (not stored)

## Build & run

```bash
cd ~/PowerSet
chmod +x build-app.sh
./build-app.sh
```

Build without launching:

```bash
./build-app.sh --no-launch
```

Optional install:

```bash
cp -R PowerSet.app /Applications/
```

## Testing a schedule

To confirm a restart schedule without waiting for the real day/time:

1. In the **Schedule** tab, pick **Restart**, the days you want, and a time a few minutes ahead.
2. Click **Apply Schedule** and enter your admin password.
3. Confirm under **Current schedule** (or run `pmset -g sched` in Terminal — **no trailing period**).
4. Stay **awake and logged in** until that time.

When the event fires, macOS normally shows a **system** notice that the Mac will restart, with options such as restart now or **postpone / try again later** (often about **10 minutes**). Seeing that dialog means the schedule worked.

### The postpone / “reschedule in ~10 minutes” dialog

That UI is built into macOS (loginwindow / power management), not PowerSet.

| Question | Answer |
|----------|--------|
| Is it configurable? | **No** — there is no supported System Settings, `pmset`, or `defaults` control for the postpone length. |
| Can PowerSet change it? | **No** — PowerSet only sets/cancels the schedule via `pmset`. |
| Why does it exist? | So open apps and unsaved work are not cut off without warning when someone is logged in. |

If you need a different warning model (e.g. a short `shutdown` countdown you choose yourself), that is a separate approach (e.g. a LaunchDaemon running `shutdown -r +1`), not Energy Saver / `pmset repeat`.

### When a scheduled restart may not fire

Even with a valid schedule (`pmset -g sched` shows the event):

- Mac is **asleep** or at the **login window** (Apple documents that shutdown/restart schedules generally need the Mac **awake and logged in**).
- **Unsaved documents** can cancel or block the power event.
- **FileVault** does not block the schedule, but after any reboot you must unlock the disk at pre-boot login.
- Apps holding sleep assertions (e.g. `caffeinate`) can interfere with sleep-related events; restart is separate but the Mac still needs to reach the scheduled moment while interactive.

## Terminal tips

```bash
# View schedule (no period at the end of "sched")
pmset -g sched

# Apply (one line — do not break after "repeat")
sudo pmset repeat restart MTWRFSU 05:00:00

# Cancel
sudo pmset repeat cancel
```

Common paste mistakes:

- Splitting the command across two lines so the shell runs `restart` as its own command (`zsh: command not found: restart`).
- Running `pmset -g sched.` with a trailing `.` → `Error: unhandled argument sched.`

## Notes

- Uses the system admin authorization dialog; the password is never stored. Choose **PowerSet → Forget Authorization** to clear the session cache.  
- Documented schedule types are `sleep`, `wake`, `poweron`, `shutdown`, and `wakeorpoweron`. **Restart** is included because it is commonly used (`pmset repeat restart …`); if your macOS rejects it, pick **Shut Down** or **Wake or Power On** instead.  
- macOS only keeps one repeating power-on-style event and one power-off-style event at a time.  
