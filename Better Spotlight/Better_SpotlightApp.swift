import AppKit

/// Strong lifetime + explicit NSApplicationMain (reliable for LSUIElement apps).
@main
enum BetterSpotlightApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var launchTime = Date.distantPast

    func applicationWillFinishLaunching(_ notification: Notification) {
        DebugLog.log("willFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("didFinishLaunching")
        Task { @MainActor in
            self.bootstrap()
        }
    }

    @MainActor
    private func bootstrap() {
        launchTime = Date()
        DebugLog.log("bootstrap")

        LoginItemManager.ensureEnabled()
        syncMenuBarIcon()
        PanelController.shared.start()

        NotificationCenter.default.addObserver(
            forName: .hotkeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusItemTooltip() }
        }

        NotificationCenter.default.addObserver(
            forName: .menuBarIconSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncMenuBarIcon() }
        }

        if SettingsStore.shouldPresentWelcome {
            DebugLog.log("show welcome")
            OnboardingWindowController.show()
        } else if !AppIndexer.shared.hasCachedApps {
            AppIndexer.shared.refresh()
        }

        DebugLog.log("bootstrap done \(PanelController.shared.hotKeyStatus)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard Date().timeIntervalSince(launchTime) > 1.5 else { return false }

        Task { @MainActor in
            if SettingsStore.shared.showMenuBarIcon {
                PanelController.shared.show()
            } else {
                SettingsWindowController.show()
            }
        }
        return false
    }

    @MainActor
    private func syncMenuBarIcon() {
        if SettingsStore.shared.showMenuBarIcon {
            installStatusItem()
        } else {
            removeStatusItem()
        }
    }

    @MainActor
    private func installStatusItem() {
        guard statusItem == nil else {
            refreshStatusItemTooltip()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let logo = NSImage(named: "AppLogo") {
                let icon = logo.copy() as? NSImage ?? logo
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(
                    systemSymbolName: "magnifyingglass",
                    accessibilityDescription: "Better Spotlight"
                )
                button.image?.isTemplate = true
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusItemTooltip()
    }

    @MainActor
    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @MainActor
    private func refreshStatusItemTooltip() {
        let shortcut = SettingsStore.shared.selectedPreset.display
        statusItem?.button?.toolTip = "Better Spotlight · \(shortcut)"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        Task { @MainActor in
            guard let event = NSApp.currentEvent else {
                PanelController.shared.toggle()
                return
            }
            if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
                self.showStatusMenu()
            } else {
                PanelController.shared.toggle()
            }
        }
    }

    @MainActor
    private func showStatusMenu() {
        guard let statusItem else { return }
        let shortcut = SettingsStore.shared.selectedPreset.display
        let menu = NSMenu()

        let show = NSMenuItem(title: "Show Launcher (\(shortcut))", action: #selector(showLauncher), keyEquivalent: "")
        let settings = NSMenuItem(title: "Better Spotlight Settings…", action: #selector(openSettings), keyEquivalent: ",")
        let refresh = NSMenuItem(title: "Refresh Apps", action: #selector(refreshApps), keyEquivalent: "r")
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Apps")
        let quit = NSMenuItem(title: "Quit Better Spotlight", action: #selector(quitApp), keyEquivalent: "q")

        for item in [show, settings, refresh, quit] {
            item.target = self
        }

        menu.addItem(show)
        menu.addItem(settings)
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async {
            statusItem.menu = nil
        }
    }

    @objc private func showLauncher() {
        Task { @MainActor in PanelController.shared.show() }
    }

    @objc private func openSettings() {
        Task { @MainActor in SettingsWindowController.show() }
    }

    @objc private func refreshApps() {
        Task { @MainActor in AppIndexer.shared.refresh() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
