# PowerSet

A simple macOS GUI for Apple’s `pmset` power-management tool.

**Version:** 1.0.5 (build 6) — see [CHANGELOG.md](CHANGELOG.md).

| | |
|--|--|
| **Marketing version** | 1.0.5 |
| **Build** | 6 |
| **Minimum macOS** | 13.0 |
| **Bundle ID** | `com.powerset.app` |

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
- Collapsible **Testing & the restart dialog** help (disclosure, collapsed by default)  

### Settings tab

Edit common timers and flags. **Apply to** chooses which `pmset` profile is loaded and written:

| Apply to | Loads from | Writes with |
|----------|------------|-------------|
| All (AC + Battery) | AC Power section of `pmset -g custom` (template), or live if missing | `pmset -a …` |
| Battery only | Battery Power section of custom | `pmset -b …` |
| AC Power only | AC Power section of custom | `pmset -c …` |

Changing scope or **Reload** re-reads that profile. After **Apply**, the form reloads the **same** scope so AC values cannot silently overwrite Battery (and vice versa). Desktops without a Battery Power section show defaults and a warning—not AC values labeled as battery.

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

**Capabilities:** keys not listed in `pmset -g cap` for the selected scope are dimmed and skipped on Apply. A scope the report does not mention at all (Battery on a desktop) disables every setting. If the report cannot be read, the controls stay enabled and Apply still tries each key. Supported keys are written one at a time so a rejection names the failing setting.

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

This builds a release binary, packages `PowerSet.app`, ad-hoc signs it, and opens it. Version is read from `AppInfo.plist`.

Build without launching:

```bash
./build-app.sh --no-launch
```

Optional install:

```bash
cp -R PowerSet.app /Applications/
```

### Regenerating the app icon

```bash
cd ~/PowerSet
swift Scripts/GenerateAppIcon.swift
```

| Output | Purpose |
|--------|---------|
| `Assets/AppIcon.icns` | Bundled into the app |
| `Assets/AppIcon-1024.png` | Source / marketing size |
| `Assets/AppIcon.iconset/` | Clean size PNGs only (`icon_16x16.png` … `icon_1024x1024.png`) |

Apple’s `@2x` names are used only in a **temporary** folder while `iconutil` builds the `.icns`; they are not left in the project tree (Finder often mis-displays `@` in filenames as email-like “Document” entries).

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

# Per-source profiles (what Settings loads)
pmset -g custom
```

Common paste mistakes:

- Splitting the command across two lines so the shell runs `restart` as its own command (`zsh: command not found: restart`).  
- Running `pmset -g sched.` with a trailing `.` → `Error: unhandled argument sched.`  

## Project layout

```
PowerSet/
├── AppInfo.plist          # Bundle version 1.0.5 / build 6
├── Package.swift
├── build-app.sh           # Release build → PowerSet.app
├── CHANGELOG.md
├── README.md
├── .gitignore
├── Assets/
│   ├── AppIcon.icns
│   ├── AppIcon-1024.png
│   └── AppIcon.iconset/   # Clean size PNGs (no @2x names)
├── Scripts/
│   └── GenerateAppIcon.swift
└── Sources/PowerSet/
    ├── MainEntry.swift         # App lifecycle, menus, About
    ├── ContentView.swift       # Schedule / Settings / Status UI
    ├── PmsetService.swift      # pmset read/write, scope parsing
    └── PrivilegedSession.swift # Session admin auth (no password storage)
```

## Architecture notes

- **`PmsetService`** isolates system behavior from SwiftUI: shared argument builders for previews and execution, scope-aware `parseSettings(for:)`, capability filtering via `pmset -g cap`, per-key apply with named failures, privileged writes with shell-escaped tokens.  
- **`ContentView`** obtains admin rights on the main thread (password dialog), then runs `pmset` on a background queue so the UI stays responsive.  
- **`PrivilegedSession`** caches an admin `AuthorizationRef` for the process only; **PowerSet → Forget Authorization** clears it.  
- Writes use the deprecated **`AuthorizationExecuteWithPrivileges`** API (via runtime lookup). That is acceptable for a **personal, locally built** utility. A polished, broadly distributed app would normally use a privileged helper with Authorization Services / XPC—only worth that complexity if you ship PowerSet widely.  

## Notes

- The password is never stored.  
- Documented schedule types are `sleep`, `wake`, `poweron`, `shutdown`, and `wakeorpoweron`. **Restart** is included because it is commonly used (`pmset repeat restart …`); if your macOS rejects it, pick **Shut Down** or **Wake or Power On** instead.  
- macOS only keeps one repeating power-on-style event and one power-off-style event at a time.  
- Built app (`PowerSet.app/`) is produced by `./build-app.sh` and is gitignored; rebuild from source after pulling.  
