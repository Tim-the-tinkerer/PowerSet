import SwiftUI

struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case schedule = "Schedule"
        case settings = "Settings"
        case status = "Status"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .schedule: return "calendar.badge.clock"
            case .settings: return "slider.horizontal.3"
            case .status: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .schedule

    // Schedule
    @State private var eventType: PmsetService.EventType = .restart
    @State private var selectedDays: Set<PmsetService.Weekday> = [.sunday]
    @State private var eventTime: Date = Self.defaultEventTime()
    @State private var scheduleStatusText = ""
    @State private var showTestingHelp = false

    // Settings
    @State private var powerScope: PmsetService.PowerScope = .all
    @State private var settings = PmsetService.PowerSettings()
    @State private var settingsSourceDescription = ""
    @State private var settingsLoadWarning: String?
    /// False until `pmset -g cap` has been read. Unknown capabilities leave controls enabled.
    @State private var capabilitiesKnown = false
    @State private var supportedSettingKeys: Set<String> = []
    @State private var settingsLoadGeneration: UInt64 = 0
    @State private var statusRefreshGeneration: UInt64 = 0

    // Shared status line
    @State private var statusMessage: String?
    @State private var statusIsError = false
    /// Which in-flight job owns the busy flag. A newer job replaces the owner,
    /// so a superseded refresh cannot leave the controls disabled.
    @State private var busyKind: BusyKind = .idle

    private enum BusyKind: Equatable {
        case idle
        case settingsLoad(UInt64)
        case statusRefresh(UInt64)
        case action
    }

    private var isBusy: Bool { busyKind != .idle }
    @State private var sessionAuthorized = false
    @State private var liveStatusText = ""

    private let workQueue = DispatchQueue(label: "com.powerset.app.work", qos: .userInitiated)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Label(t.rawValue, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityLabel("Section")

            Group {
                switch tab {
                case .schedule:
                    schedulePane
                case .settings:
                    settingsPane
                case .status:
                    statusPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: .powerSetAuthorizationDidChange)) { _ in
            sessionAuthorized = PrivilegedSession.shared.isAuthorized
            if !sessionAuthorized {
                setStatus("Administrator authorization cleared for this session.", error: false)
            }
        }
        .onChange(of: tab) { newTab in
            if newTab == .status || newTab == .schedule {
                refreshScheduleAndLive(announce: false)
            }
            if newTab == .settings {
                reloadSettingsForCurrentScope(announce: false)
            }
        }
        .onChange(of: powerScope) { _ in
            reloadSettingsForCurrentScope(announce: true)
        }
    }

    // MARK: - Defaults

    private static func defaultEventTime() -> Date {
        Calendar.current.date(bySettingHour: 5, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text("PowerSet")
                    .font(.headline)
                Spacer(minLength: 0)
                authBadge
            }

            Text("GUI for sudo pmset — schedule repeating power events and edit sleep timers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authBadge: some View {
        Text(sessionAuthorized ? "Admin ready" : "Admin when needed")
            .font(.caption.weight(.medium))
            .foregroundStyle(sessionAuthorized ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(nsColor: .controlBackgroundColor))
            )
            .accessibilityLabel(
                sessionAuthorized
                    ? "Administrator authorization ready"
                    : "Administrator authorization will be requested when needed"
            )
            .help(
                sessionAuthorized
                    ? "Administrator rights cached for this app session. PowerSet → Forget Authorization to clear."
                    : "macOS will ask for your password when you apply changes."
            )
    }

    // MARK: - Schedule

    private var schedulePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Event") {
                            Picker("Event type", selection: $eventType) {
                                ForEach(PmsetService.EventType.allCases) { t in
                                    Text(t.label).tag(t)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200, alignment: .trailing)
                        }

                        LabeledContent("Time") {
                            DatePicker(
                                "Time",
                                selection: $eventTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .frame(maxWidth: 140, alignment: .trailing)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weekdays")
                                .font(.subheadline.weight(.medium))
                            weekdayPicker
                            HStack(spacing: 8) {
                                Button("Weekdays") {
                                    selectedDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
                                }
                                .controlSize(.small)
                                .disabled(isBusy)
                                Button("Every day") {
                                    selectedDays = Set(PmsetService.Weekday.allCases)
                                }
                                .controlSize(.small)
                                .disabled(isBusy)
                                Button("Clear") {
                                    selectedDays = []
                                }
                                .controlSize(.small)
                                .disabled(isBusy)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Command preview")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(repeatCommandPreview)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(selectedDays.isEmpty ? .secondary : .primary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .accessibilityLabel("Command preview: \(repeatCommandPreview)")
                        }

                        HStack(spacing: 10) {
                            Button {
                                applyRepeat()
                            } label: {
                                Label("Apply Schedule", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(isBusy || selectedDays.isEmpty)
                            .keyboardShortcut(.defaultAction)
                            .help("Runs the previewed sudo pmset repeat command")

                            Button(role: .destructive) {
                                cancelRepeat()
                            } label: {
                                Label("Cancel Schedule", systemImage: "xmark.circle")
                            }
                            .disabled(isBusy)
                            .help("Runs sudo pmset repeat cancel")
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Repeating power event", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current schedule")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                refreshScheduleAndLive(announce: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh schedule")
                            .disabled(isBusy)
                            .accessibilityLabel("Refresh schedule")
                        }

                        Text(scheduleStatusText.isEmpty ? "No schedule info." : scheduleStatusText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }
                    .padding(4)
                } label: {
                    Label("pmset -g sched", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                }

                DisclosureGroup(isExpanded: $showTestingHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            """
                            Set Restart to a time a few minutes ahead, apply, and stay awake and logged in. When it fires, macOS shows its own restart notice — often with a “try again later” / postpone option of about 10 minutes. That dialog means the schedule worked.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text("The ~10 minute postpone is fixed system behavior")
                            .font(.caption.weight(.semibold))
                        Text(
                            """
                            PowerSet and pmset cannot change that timer. There is no System Settings or defaults control for it. It exists so you can save work before a scheduled restart. For a different warning style, you would need another mechanism (for example a LaunchDaemon running shutdown), not this schedule.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text("A scheduled restart may not fire if the Mac is asleep, at the login window, or blocked by unsaved documents. Verify anytime with Current schedule above (or pmset -g sched — no trailing period).")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Testing & the restart dialog", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 4)

                Text("Note: macOS allows one repeating power-on style event and one power-off style event. Applying a new schedule replaces the previous matching type.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(PmsetService.Weekday.allCases) { day in
                let on = selectedDays.contains(day)
                Button {
                    if on {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? Color.orange.opacity(0.85) : Color(nsColor: .controlBackgroundColor))
                        )
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help(day.accessibilityLabel)
                .accessibilityLabel(day.accessibilityLabel)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityValue(on ? "Selected" : "Not selected")
            }
        }
    }

    private var repeatCommandPreview: String {
        if let args = PmsetService.repeatArguments(type: eventType, weekdays: selectedDays, time: eventTime) {
            return PmsetService.commandPreview(arguments: args)
        }
        return "sudo pmset repeat …  (select at least one weekday)"
    }

    // MARK: - Settings

    private var settingsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Apply to") {
                            Picker("Power scope", selection: $powerScope) {
                                ForEach(PmsetService.PowerScope.allCases) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .trailing)
                            .disabled(isBusy)
                            .help("Loads and writes the matching pmset profile (custom AC / Battery, or -a for all).")
                        }

                        if !settingsSourceDescription.isEmpty {
                            Text("Loaded from: \(settingsSourceDescription)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let settingsLoadWarning {
                            Text(settingsLoadWarning)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if capabilitiesKnown {
                            let unsupported = PmsetService.managedSettingKeys.filter { !supportedSettingKeys.contains($0) }
                            if !unsupported.isEmpty {
                                Text("Not supported on this Mac/scope (pmset -g cap): \(unsupported.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        timerRow(
                            title: "Display sleep",
                            key: "displaysleep",
                            help: "Minutes until the display sleeps. 0 = never.",
                            value: $settings.displaysleep
                        )
                        timerRow(
                            title: "System sleep",
                            key: "sleep",
                            help: "Minutes until the Mac sleeps. 0 = never.",
                            value: $settings.sleep
                        )
                        timerRow(
                            title: "Disk sleep",
                            key: "disksleep",
                            help: "Minutes until disks spin down. 0 = never.",
                            value: $settings.disksleep
                        )

                        Divider()

                        settingToggle("Wake for network access (womp)", key: "womp", isOn: $settings.womp)
                        settingToggle("Power Nap", key: "powernap", isOn: $settings.powernap)
                        settingToggle("Auto-restart after power loss", key: "autorestart", isOn: $settings.autorestart)
                        settingToggle("Keep awake for active TTYs", key: "ttyskeepawake", isOn: $settings.ttyskeepawake)
                        settingToggle("Proximity wake", key: "proximitywake", isOn: $settings.proximitywake)
                        settingToggle("TCP keepalive during sleep", key: "tcpkeepalive", isOn: $settings.tcpkeepalive)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Command preview (batch form)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(settingsCommandPreview)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .accessibilityLabel("Command preview: \(settingsCommandPreview)")
                            Text("Apply sends supported keys one at a time so rejections name the failing setting.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                applySettings()
                            } label: {
                                Label("Apply Settings", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(isBusy)
                            .help("Applies supported settings for this scope as administrator")

                            Button {
                                reloadSettingsForCurrentScope(announce: true)
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                            .disabled(isBusy)
                            .help("Re-read the selected power profile and capabilities")
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Sleep timers & options", systemImage: "moon.zzz")
                        .font(.subheadline.weight(.semibold))
                }

                GroupBox {
                    HStack(spacing: 10) {
                        Button {
                            runUnprivilegedWork({ PmsetService.displaySleepNow() }, successFallback: "Display sleeping…")
                        } label: {
                            Label("Sleep Display Now", systemImage: "display")
                        }
                        .disabled(isBusy)
                        .help("pmset displaysleepnow")

                        Button {
                            runUnprivilegedWork({ PmsetService.sleepNow() }, successFallback: "Sleeping…")
                        } label: {
                            Label("Sleep Mac Now", systemImage: "moon.fill")
                        }
                        .disabled(isBusy)
                        .help("pmset sleepnow")
                    }
                    .padding(4)
                } label: {
                    Label("Immediate actions", systemImage: "bolt")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func isSettingSupported(_ key: String) -> Bool {
        // Unknown capabilities → leave all controls enabled.
        // A known empty set (Battery on a desktop) disables every control.
        !capabilitiesKnown || supportedSettingKeys.contains(key)
    }

    private func settingToggle(_ title: String, key: String, isOn: Binding<Bool>) -> some View {
        let supported = isSettingSupported(key)
        return Toggle(title, isOn: isOn)
            .disabled(isBusy || !supported)
            .help(supported ? title : "Not listed in pmset -g cap for this Mac/scope")
            .opacity(supported ? 1 : 0.45)
    }

    private func timerRow(title: String, key: String, help: String, value: Binding<Int>) -> some View {
        let supported = isSettingSupported(key)
        return HStack {
            Text(title)
                .help(supported ? help : "\(help) Not supported on this Mac/scope.")
                .opacity(supported ? 1 : 0.45)
            Spacer()
            Stepper(value: value, in: 0...180, step: 1) {
                Text(value.wrappedValue == 0 ? "Never" : "\(value.wrappedValue) min")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 72, alignment: .trailing)
            }
            .frame(maxWidth: 200)
            .disabled(isBusy || !supported)
            .help(supported ? help : "Not listed in pmset -g cap for this Mac/scope")
            .accessibilityLabel(title)
            .accessibilityValue(value.wrappedValue == 0 ? "Never" : "\(value.wrappedValue) minutes")
        }
    }

    private var settingsCommandPreview: String {
        PmsetService.commandPreview(
            arguments: PmsetService.settingsArguments(settings, scope: powerScope)
        )
    }

    // MARK: - Status

    private var statusPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Live power settings")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                refreshScheduleAndLive(announce: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(isBusy)
                            .accessibilityLabel("Refresh live power settings")
                        }
                        Text(liveStatusText.isEmpty ? "—" : liveStatusText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }
                    .padding(4)
                } label: {
                    Label("pmset -g", systemImage: "gauge")
                        .font(.subheadline.weight(.semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current schedule")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                refreshScheduleAndLive(announce: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(isBusy)
                            .accessibilityLabel("Refresh schedule status")
                        }
                        Text(scheduleStatusText.isEmpty ? "—" : scheduleStatusText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }
                    .padding(4)
                } label: {
                    Label("pmset -g sched", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            }
            if let statusMessage {
                Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(statusIsError ? Color.orange : Color.green)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.primary : Color.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .accessibilityLabel(statusIsError ? "Error: \(statusMessage)" : statusMessage)
            } else {
                Text("Changes require administrator approval via the macOS password dialog.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }

    // MARK: - Actions (auth on main, pmset work off main)

    private func applyRepeat() {
        guard !isBusy else { return }
        guard !selectedDays.isEmpty else {
            setStatus("Select at least one weekday.", error: true)
            return
        }
        let type = eventType
        let days = selectedDays
        let time = eventTime
        runPrivilegedWork(
            { PmsetService.applyRepeat(type: type, weekdays: days, time: time) },
            successFallback: "Schedule applied."
        ) {
            self.refreshScheduleAndLive(announce: false)
        }
    }

    private func cancelRepeat() {
        guard !isBusy else { return }
        runPrivilegedWork(
            { PmsetService.cancelRepeat() },
            successFallback: "Repeating schedule cancelled."
        ) {
            self.refreshScheduleAndLive(announce: false)
        }
    }

    private func applySettings() {
        guard !isBusy else { return }
        let s = settings
        let scope = powerScope
        runPrivilegedWork(
            { PmsetService.applySettings(s, scope: scope) },
            successFallback: "Power settings applied to \(scope.label)."
        ) {
            self.refreshScheduleAndLive(announce: false)
            self.reloadSettingsForCurrentScope(announce: false)
        }
    }

    /// Password dialog on the main thread; `pmset` work on a background queue.
    private func runPrivilegedWork(
        _ work: @escaping () -> PmsetService.ActionResult,
        successFallback: String,
        then onComplete: (() -> Void)? = nil
    ) {
        guard !isBusy else { return }
        busyKind = .action
        statusMessage = nil

        // Let the busy indicator paint, then authorize (UI must be main-thread).
        DispatchQueue.main.async {
            switch PrivilegedSession.shared.ensureAuthorized() {
            case .cancelled:
                self.handle(.cancelled, successFallback: successFallback)
                self.busyKind = .idle
                return
            case .failed(let message):
                self.handle(.failed(message), successFallback: successFallback)
                self.busyKind = .idle
                return
            case .success:
                break
            }

            self.workQueue.async {
                let result = work()
                DispatchQueue.main.async {
                    self.handle(result, successFallback: successFallback)
                    self.sessionAuthorized = PrivilegedSession.shared.isAuthorized
                    self.busyKind = .idle
                    onComplete?()
                }
            }
        }
    }

    private func runUnprivilegedWork(
        _ work: @escaping () -> PmsetService.ActionResult,
        successFallback: String
    ) {
        guard !isBusy else { return }
        busyKind = .action
        statusMessage = nil
        workQueue.async {
            let result = work()
            DispatchQueue.main.async {
                self.handle(result, successFallback: successFallback)
                self.busyKind = .idle
            }
        }
    }

    private func handle(_ result: PmsetService.ActionResult, successFallback: String) {
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            // Partial apply messages that include "Failed:" still succeed overall but surface as caution.
            let caution = trimmed.localizedCaseInsensitiveContains("failed:")
                || trimmed.localizedCaseInsensitiveContains("skipped")
            setStatus(trimmed.isEmpty ? successFallback : trimmed, error: caution)
        case .cancelled:
            setStatus("Cancelled — no changes made.", error: true)
        case .failed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            setStatus(trimmed.isEmpty ? "Operation failed." : trimmed, error: true)
        }
    }

    private func setStatus(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }

    /// Load form fields from the profile that matches ``powerScope`` (off main thread).
    private func reloadSettingsForCurrentScope(announce: Bool) {
        settingsLoadGeneration &+= 1
        let generation = settingsLoadGeneration
        let scope = powerScope
        if announce {
            busyKind = .settingsLoad(generation)
            statusMessage = nil
        } else if case .settingsLoad = busyKind {
            // This load replaces an announced one. That one will not clear the flag.
            busyKind = .idle
        }

        workQueue.async {
            let loaded = PmsetService.parseSettings(for: scope)
            DispatchQueue.main.async {
                guard generation == self.settingsLoadGeneration else { return }
                self.settings = loaded.settings
                self.settingsSourceDescription = loaded.sourceDescription
                self.settingsLoadWarning = loaded.warning
                self.supportedSettingKeys = loaded.capabilities.keys
                self.capabilitiesKnown = loaded.capabilities.known
                guard case .settingsLoad(let token) = self.busyKind, token == generation else { return }
                if let warning = loaded.warning {
                    self.setStatus(
                        "Reloaded \(scope.label) from \(loaded.sourceDescription). \(warning)",
                        error: true
                    )
                } else {
                    self.setStatus(
                        "Reloaded \(scope.label) from \(loaded.sourceDescription).",
                        error: false
                    )
                }
                self.busyKind = .idle
            }
        }
    }

    private func refreshAll() {
        sessionAuthorized = PrivilegedSession.shared.isAuthorized
        reloadSettingsForCurrentScope(announce: false)
        refreshScheduleAndLive(announce: false)
    }

    private func refreshScheduleAndLive(announce: Bool) {
        statusRefreshGeneration &+= 1
        let generation = statusRefreshGeneration
        if announce {
            busyKind = .statusRefresh(generation)
        } else if case .statusRefresh = busyKind {
            // This refresh replaces an announced one. That one will not clear the flag.
            busyKind = .idle
        }
        workQueue.async {
            let schedule = PmsetService.scheduleStatus()
            let live = PmsetService.liveStatus()
            DispatchQueue.main.async {
                guard generation == self.statusRefreshGeneration else { return }
                self.scheduleStatusText = schedule
                self.liveStatusText = live
                guard case .statusRefresh(let token) = self.busyKind, token == generation else { return }
                self.setStatus("Status refreshed.", error: false)
                self.busyKind = .idle
            }
        }
    }
}
