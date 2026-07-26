import Foundation

/// Thin wrapper around `/usr/bin/pmset` for reading and writing power settings.
enum PmsetService {
    static let pmsetPath = "/usr/bin/pmset"

    // MARK: - Models

    enum EventType: String, CaseIterable, Identifiable {
        case restart
        case shutdown
        case sleep
        case wake
        case poweron
        case wakeorpoweron

        var id: String { rawValue }

        var label: String {
            switch self {
            case .restart: return "Restart"
            case .shutdown: return "Shut Down"
            case .sleep: return "Sleep"
            case .wake: return "Wake"
            case .poweron: return "Power On"
            case .wakeorpoweron: return "Wake or Power On"
            }
        }
    }

    enum Weekday: String, CaseIterable, Identifiable {
        case monday = "M"
        case tuesday = "T"
        case wednesday = "W"
        case thursday = "R"
        case friday = "F"
        case saturday = "S"
        case sunday = "U"

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            case .sunday: return "Sun"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
            case .sunday: return "Sunday"
            }
        }
    }

    /// Power-source scope for settings (`pmset -a/-b/-c`).
    enum PowerScope: String, CaseIterable, Identifiable {
        case all = "-a"
        case battery = "-b"
        case charger = "-c"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All (AC + Battery)"
            case .battery: return "Battery only"
            case .charger: return "AC Power only"
            }
        }
    }

    struct PowerSettings: Equatable {
        /// Minutes; 0 = never. Values are clamped to 0…180 when applying.
        var displaysleep: Int = 10
        var sleep: Int = 10
        var disksleep: Int = 10
        var womp: Bool = true
        var powernap: Bool = true
        var autorestart: Bool = false
        var ttyskeepawake: Bool = true
        var proximitywake: Bool = false
        var tcpkeepalive: Bool = true

        /// Clamped copy suitable for `pmset`.
        func clamped() -> PowerSettings {
            var copy = self
            copy.displaysleep = min(max(displaysleep, 0), 180)
            copy.sleep = min(max(sleep, 0), 180)
            copy.disksleep = min(max(disksleep, 0), 180)
            return copy
        }
    }

    enum ActionResult: Equatable {
        case success(String)
        case cancelled
        case failed(String)
    }

    // MARK: - Read (unprivileged)

    /// Current scheduled events (`pmset -g sched`).
    static func scheduleStatus() -> String {
        let result = runUnprivileged(arguments: ["-g", "sched"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Settings currently in use (`pmset -g`).
    static func liveStatus() -> String {
        let result = runUnprivileged(arguments: ["-g"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Custom (AC / Battery) settings dump.
    static func customStatus() -> String {
        let result = runUnprivileged(arguments: ["-g", "custom"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort parse of live settings into editable fields.
    static func parseLiveSettings() -> PowerSettings {
        let text = liveStatus()
        var s = PowerSettings()
        s.displaysleep = intValue(for: "displaysleep", in: text) ?? s.displaysleep
        s.sleep = intValue(for: "sleep", in: text) ?? s.sleep
        s.disksleep = intValue(for: "disksleep", in: text) ?? s.disksleep
        s.womp = boolValue(for: "womp", in: text) ?? s.womp
        s.powernap = boolValue(for: "powernap", in: text) ?? s.powernap
        s.autorestart = boolValue(for: "autorestart", in: text) ?? s.autorestart
        s.ttyskeepawake = boolValue(for: "ttyskeepawake", in: text) ?? s.ttyskeepawake
        s.proximitywake = boolValue(for: "proximitywake", in: text) ?? s.proximitywake
        s.tcpkeepalive = boolValue(for: "tcpkeepalive", in: text) ?? s.tcpkeepalive
        return s
    }

    // MARK: - Argument builders

    /// Builds argv for `pmset repeat <type> <weekdays> <HH:mm:ss>`.
    static func repeatArguments(type: EventType, weekdays: Set<Weekday>, time: Date) -> [String]? {
        let dayString = Weekday.allCases
            .filter { weekdays.contains($0) }
            .map(\.rawValue)
            .joined()
        guard !dayString.isEmpty else { return nil }

        return ["repeat", type.rawValue, dayString, formatTime(time)]
    }

    /// Builds argv for applying common timers/toggles under a power scope.
    static func settingsArguments(_ settings: PowerSettings, scope: PowerScope) -> [String] {
        let s = settings.clamped()
        return [
            scope.rawValue,
            "displaysleep", String(s.displaysleep),
            "sleep", String(s.sleep),
            "disksleep", String(s.disksleep),
            "womp", s.womp ? "1" : "0",
            "powernap", s.powernap ? "1" : "0",
            "autorestart", s.autorestart ? "1" : "0",
            "ttyskeepawake", s.ttyskeepawake ? "1" : "0",
            "proximitywake", s.proximitywake ? "1" : "0",
            "tcpkeepalive", s.tcpkeepalive ? "1" : "0",
        ]
    }

    /// Human-readable command preview (with sudo for display only).
    static func commandPreview(arguments: [String]) -> String {
        let joined = arguments.map { shellQuoteForDisplay($0) }.joined(separator: " ")
        return "sudo pmset \(joined)"
    }

    // MARK: - Write (privileged)

    /// `sudo pmset repeat <type> <days> <time>`
    static func applyRepeat(type: EventType, weekdays: Set<Weekday>, time: Date) -> ActionResult {
        guard let args = repeatArguments(type: type, weekdays: weekdays, time: time) else {
            return .failed("Select at least one weekday.")
        }
        return runPrivileged(arguments: args)
    }

    /// `sudo pmset repeat cancel`
    static func cancelRepeat() -> ActionResult {
        runPrivileged(arguments: ["repeat", "cancel"])
    }

    /// Apply common timer / toggle settings under a power scope.
    static func applySettings(_ settings: PowerSettings, scope: PowerScope) -> ActionResult {
        runPrivileged(arguments: settingsArguments(settings, scope: scope))
    }

    /// Immediate system sleep (unprivileged).
    static func sleepNow() -> ActionResult {
        let result = runUnprivileged(arguments: ["sleepnow"])
        if result.exitCode != 0 {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(detail.isEmpty ? "Could not sleep (exit \(result.exitCode))." : detail)
        }
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.lowercased().contains("error") {
            return .failed(out)
        }
        return .success(out.isEmpty ? "Sleeping…" : out)
    }

    /// Immediate display sleep (unprivileged).
    static func displaySleepNow() -> ActionResult {
        let result = runUnprivileged(arguments: ["displaysleepnow"])
        if result.exitCode != 0 {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(detail.isEmpty ? "Could not sleep display (exit \(result.exitCode))." : detail)
        }
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.lowercased().contains("error") {
            return .failed(out)
        }
        return .success(out.isEmpty ? "Display sleeping…" : out)
    }

    // MARK: - Process helpers

    /// Runs pmset as root and requires a successful shell exit (AEWP does not return exit codes).
    private static func runPrivileged(arguments: [String]) -> ActionResult {
        guard FileManager.default.isExecutableFile(atPath: pmsetPath) else {
            return .failed("Could not find \(pmsetPath).")
        }

        // Escape every token for /bin/sh -c; never interpolate raw user strings unescaped.
        let quotedArgs = arguments.map(shellEscape).joined(separator: " ")
        let script = """
        \(shellEscape(pmsetPath)) \(quotedArgs)
        """

        switch PrivilegedSession.shared.runShell(script) {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            // pmset often prints nothing on success; treat clear failure text as errors.
            let lower = trimmed.lowercased()
            if lower.contains("error:")
                || lower.contains("unhandled argument")
                || lower.hasPrefix("usage:")
                || lower.contains("\nusage:")
            {
                return .failed(trimmed)
            }
            return .success(trimmed)
        case .cancelled:
            return .cancelled
        case .failed(let message):
            return .failed(message)
        }
    }

    private struct ProcessResult {
        var output: String
        var exitCode: Int32
    }

    private static func runUnprivileged(arguments: [String]) -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: pmsetPath) else {
            return ProcessResult(output: "Error: \(pmsetPath) is not available.", exitCode: 127)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pmsetPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return ProcessResult(output: text, exitCode: process.terminationStatus)
        } catch {
            return ProcessResult(output: "Error: \(error.localizedDescription)", exitCode: -1)
        }
    }

    /// Exact key match: key must be followed by whitespace (avoids `autorestart` matching `autorestartatconnect`).
    private static func intValue(for key: String, in text: String) -> Int? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let afterKey = trimmed.dropFirst(key.count)
            guard let first = afterKey.first, first.isWhitespace else { continue }
            let rest = afterKey.trimmingCharacters(in: .whitespaces)
            // Value may be followed by parenthetical notes: "0 (sleep prevented by …)"
            let token = rest.prefix(while: { $0.isNumber || $0 == "-" || $0 == "+" })
            if let value = Int(token) {
                return value
            }
        }
        return nil
    }

    private static func boolValue(for key: String, in text: String) -> Bool? {
        guard let value = intValue(for: key, in: text) else { return nil }
        return value != 0
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Single-quote shell escape for privileged scripts.
    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func shellQuoteForDisplay(_ arg: String) -> String {
        if arg.range(of: #"[\s\"'\\]"#, options: .regularExpression) != nil {
            return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return arg
    }
}
