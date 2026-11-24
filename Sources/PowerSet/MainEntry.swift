import AppKit
import SwiftUI

@main
struct MainEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var window: NSWindow?

    private let minSize = NSSize(width: 480, height: 560)
    private let defaultSize = NSSize(width: 520, height: 640)

    private override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Drop rights when the process exits (password was never stored).
        PrivilegedSession.shared.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .frame(minWidth: minSize.width, minHeight: minSize.height)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: defaultSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PowerSet"
        window.contentView = hosting
        window.setContentSize(defaultSize)
        window.contentMinSize = minSize
        window.isRestorable = true
        window.setFrameAutosaveName("PowerSetMain")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "PowerSet")
        appMenuItem.submenu = appMenu

        let aboutItem = appMenu.addItem(
            withTitle: "About PowerSet",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self

        appMenu.addItem(NSMenuItem.separator())

        let forgetItem = appMenu.addItem(
            withTitle: "Forget Authorization",
            action: #selector(forgetAuthorization(_:)),
            keyEquivalent: ""
        )
        forgetItem.target = self

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit PowerSet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func forgetAuthorization(_ sender: Any?) {
        PrivilegedSession.shared.invalidate()
    }

    @objc private func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.5"
        let build = info?["CFBundleVersion"] as? String ?? "6"
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "PowerSet",
            .version: version,
            .applicationVersion: "Version \(version) (\(build))",
            .credits: NSAttributedString(
                string: """
                Simple GUI for macOS pmset power management.

                Schedule repeating restart/shutdown/wake events \
                and edit sleep timers per power source (All / AC / \
                Battery). Uses the system admin dialog \
                (password is never stored).

                When a scheduled restart fires while logged in, macOS \
                may offer to postpone (~10 minutes). That timer is \
                fixed system UI and is not configurable.
                """,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ]
        if let icon = NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
