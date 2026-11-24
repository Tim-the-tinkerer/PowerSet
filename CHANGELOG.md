# Changelog

All notable changes to **PowerSet** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [1.0.5] - 2026-11-23

### Fixed

- Battery scope on a desktop no longer treats a missing Battery Power section in `pmset -g cap` as “unknown.” Those settings are dimmed and skipped instead of being offered for apply
- Refresh and Reload clear the busy state when a newer read replaces them, so the controls cannot stay disabled
- Window restoration opts into secure restorable state

### Changed

- Version **1.0.5** (build 6)

## [1.0.4] - 2026-08-01

### Fixed

- Privileged and unprivileged `pmset` work runs on a background queue after main-thread authorization, so the UI no longer freezes while tools run (busy indicator is genuine)
- Settings apply is capability-aware (`pmset -g cap`) and applies **one key at a time**, naming skipped unsupported keys and any rejections instead of aborting the whole profile on the first failure

### Changed

- Testing & restart-dialog copy is collapsed under a **DisclosureGroup** so the Schedule tab stays compact by default
- Unsupported settings for the current Mac/scope are dimmed/disabled when capabilities are known
- Version **1.0.4** (build 5)

## [1.0.3] - 2026-08-01

### Fixed

- **Settings scope correctness:** form values load from the matching `pmset -g custom` section (AC Power / Battery Power) for the selected **Apply to** scope, not only from active `pmset -g`. Changing scope or **Reload** re-reads that profile; **Apply** reloads the same scope after write so AC values cannot silently overwrite Battery (and vice versa)
- Desktops without a Battery Power section show defaults + a warning instead of pretending AC values are the battery profile

### Changed

- Settings UI shows **Loaded from:** … and an optional warning for the current profile source
- Version **1.0.3** (build 4); README documents scope-aware settings and privileged-execution tradeoffs

### Documentation

- README: scope-aware load/save behavior for All / Battery / AC
- README: architecture note on deprecated `AuthorizationExecuteWithPrivileges` (acceptable for local utilities; privileged helper recommended only if distributing broadly)

## [1.0.2] - 2026-08-01

### Fixed

- App icon packaging: build `.icns` via a temporary folder using Apple’s required `@2x` names for `iconutil`, then keep only clean archive names in `Assets/AppIcon.iconset` (`icon_16x16.png` … `icon_1024x1024.png`, no `@` in filenames)
- Icon pixel sizes match each file name (earlier dual maps had left wrong resolutions in some slots)

### Changed

- Version **1.0.2** (build 3)

## [1.0.1] - 2026-07-26

### Added

- In-app **Testing & the restart dialog** notes on the Schedule tab (how to test, ~10 minute postpone is fixed system UI, when schedules may not fire)
- README sections for testing, postpone dialog, and common Terminal paste mistakes
- About panel note that the postpone timer is not configurable
- Authorization-change notification so the **Admin ready** badge updates after **Forget Authorization**
- Window menu (Close, Minimize, Bring All to Front)
- Accessibility labels/values for weekdays, timers, previews, and status controls
- `CHANGELOG.md` and `.gitignore`

### Fixed

- Settings parse: exact `pmset` key matching so `autorestart` no longer picks up `autorestartatconnect`
- Privileged `pmset` runs: detect real failure via shell `set -e` and a success marker (AEWP does not expose exit status)
- Safer privileged argv allocation (no force-unwrap on `strdup`)
- Default schedule time built with `date(bySettingHour:minute:second:of:)` for reliable DatePicker / formatting
- Settings command preview and apply share one argument builder (no drift)
- Status tab SF Symbol uses `gauge` (macOS 13–safe; avoids 14-only gauge variants)
- Unprivileged sleep actions check process exit status
- Narrower success/failure text checks for `pmset` output
- Remove `#Preview` macro that broke pure SwiftPM release builds without Xcode preview plugins
- Clear cached admin rights on app quit
- About panel shows the app icon when available
- Reopen from Dock activates the main window when it was already open

### Changed

- Disable schedule/settings controls while a privileged or sleep action is in progress
- Clamp sleep timer fields to 0…180 minutes on apply
- POSIX time formatting with explicit calendar and local time zone for `pmset` times

## [1.0.0] - 2026-07-26

### Added

- macOS app GUI for Apple’s `/usr/bin/pmset`
- **Schedule** tab: repeating power events (Restart, Shut Down, Sleep, Wake, Power On, Wake or Power On)
- Weekday toggles (MTWRFSU) with Weekdays / Every day / Clear helpers
- Time picker and live `sudo pmset …` command preview
- Apply / Cancel schedule via system administrator authorization (password not stored)
- Current schedule display (`pmset -g sched`)
- **Settings** tab: display/system/disk sleep timers and common flags (womp, Power Nap, autorestart, TTY keep-awake, proximity wake, TCP keepalive)
- Power scope: All / Battery / AC (`-a` / `-b` / `-c`)
- Sleep Display Now / Sleep Mac Now
- **Status** tab: live `pmset -g` and schedule dump
- Session-scoped privileged execution (`AuthorizationExecuteWithPrivileges` via runtime lookup)
- **PowerSet → Forget Authorization** to drop cached admin rights
- App icon, `build-app.sh` packaging, and README
