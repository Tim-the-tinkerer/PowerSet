# Changelog

All notable changes to **PowerSet** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-07-26

### Added

- In-app **Testing & the restart dialog** notes on the Schedule tab (how to test, ~10 minute postpone is fixed system UI, when schedules may not fire)
- README sections for testing, postpone dialog, and common Terminal paste mistakes
- About panel note that the postpone timer is not configurable
- Authorization-change notification so the **Admin ready** badge updates after **Forget Authorization**
- Window menu (Close, Minimize, Bring All to Front)
- Accessibility labels/values for weekdays, timers, previews, and status controls

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
