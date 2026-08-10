import AppKit
import Carbon
import SwiftUI

@MainActor
final class PanelController {
    static let shared = PanelController()

    private var panel: SpotlightPanel?
    private let hotKey = HotKeyManager()
    private var localMonitor: Any?
    private var globalMouseMonitor: Any?
    private var isPresented = false
    private var lastShowAt: Date = .distantPast
    /// Absorbs the global hotkey echo right after a local hide on the same keypress.
    private var ignoreShowUntil: Date = .distantPast
    /// Ignore outside-clicks briefly after open (avoids instant dismiss).
    private var ignoreOutsideClicksUntil: Date = .distantPast

    private let panelWidth: CGFloat = 640
    private let panelHeight: CGFloat = 420
    /// Debounce only duplicate opens from Carbon + event tap firing together.
    private let showDebounce: TimeInterval = 0.2

    private init() {}

    func start() {
        NotificationCenter.default.addObserver(
            forName: .hotkeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.registerHotkeyFromSettings()
            }
        }

        registerHotkeyFromSettings()
    }

    func registerHotkeyFromSettings() {
        let preset = SettingsStore.shared.selectedPreset
        hotKey.register(
            keyCode: preset.keyCode,
            modifiers: preset.carbonModifiers,
            claimsSpotlight: preset.claimsSpotlight,
            alsoRegisterOptionSpaceFallback: true
        ) { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }
        NotificationCenter.default.post(
            name: .hotkeyRegistrationDidUpdate,
            object: hotKey.lastStatusMessage
        )
    }

    var hotKeyStatus: String { hotKey.lastStatusMessage }

    func toggle() {
        if isPresented {
            DebugLog.log("toggle → hide")
            hide()
            return
        }

        let now = Date()
        guard now >= ignoreShowUntil else {
            DebugLog.log("toggle ignored (post-hide echo)")
            return
        }
        guard now.timeIntervalSince(lastShowAt) >= showDebounce else {
            DebugLog.log("toggle ignored (show debounce)")
            return
        }
        lastShowAt = now
        DebugLog.log("toggle → show")
        show()
    }

    func show() {
        isPresented = true
        ignoreOutsideClicksUntil = Date().addingTimeInterval(0.45)

        attachContentIfNeeded()
        guard let panel else {
            DebugLog.log("show aborted — no panel")
            return
        }

        LauncherUIModel.shared.beginShow()

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        positionPanel(panel, display: true)
        panel.alphaValue = 1

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        DebugLog.log(
            "show frame=\(NSStringFromRect(panel.frame)) alpha=\(panel.alphaValue) key=\(panel.isKeyWindow) visible=\(panel.isVisible) hosting=\(panel.contentView is NSHostingView<SearchView>)"
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .spotlightDidShow, object: nil)
        }

        installDismissalMonitors()
    }

    func hide(reason: String = "unspecified") {
        guard isPresented else { return }
        DebugLog.log("hide reason=\(reason)")
        isPresented = false
        ignoreShowUntil = Date().addingTimeInterval(0.12)
        removeDismissalMonitors()

        LauncherUIModel.shared.beginHide()
        NotificationCenter.default.post(name: .spotlightWillHide, object: nil)

        panel?.orderOut(nil)
        AppIndexer.shared.purgeCaches()
        NotificationCenter.default.post(name: .spotlightDidHide, object: nil)
        DebugLog.log("hidden")
    }

    private func attachContentIfNeeded() {
        if panel == nil {
            let panel = SpotlightPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
            )
            self.panel = panel
            DebugLog.log("created panel")
        }

        guard let panel else { return }

        // NSPanel always ships with a default contentView — replace it with SwiftUI.
        if panel.contentView is NSHostingView<SearchView> {
            DebugLog.log("SearchView already attached")
            return
        }

        let rootView = SearchView(onDismiss: { [weak self] in
            self?.hide(reason: "search-dismiss")
        })
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        DebugLog.log("attached SearchView bounds=\(NSStringFromRect(hosting.bounds))")
    }

    private func positionPanel(_ panel: NSPanel, display: Bool = true) {
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let x = visible.midX - panelWidth / 2
        let y = visible.midY + visible.height * 0.12 - panelHeight / 2
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: display)
    }

    private func shouldIgnoreOutsideClick() -> Bool {
        Date() < ignoreOutsideClicksUntil
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown {
                if self.matchesRegisteredShortcut(event) {
                    if self.isPresented {
                        self.hide(reason: "shortcut")
                    }
                    return nil
                }

                if event.keyCode == 53 {
                    self.hide(reason: "escape")
                    return nil
                }
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if self.shouldIgnoreOutsideClick() { return event }
                if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide(reason: "local-outside-click")
                }
            }

            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.shouldIgnoreOutsideClick() { return }
            let panel = self.panel
            guard let panel, self.isPresented else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { [weak self] in
                    self?.hide(reason: "global-outside-click")
                }
            }
        }
    }

    private func removeDismissalMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func matchesRegisteredShortcut(_ event: NSEvent) -> Bool {
        let preset = SettingsStore.shared.selectedPreset
        if matches(event, preset: preset) { return true }

        // ⌥Space fallback is always registered unless it's already the primary shortcut.
        let primaryIsOptionSpace =
            preset.keyCode == UInt32(kVK_Space) && preset.carbonModifiers == UInt32(optionKey)
        if primaryIsOptionSpace { return false }

        return matches(
            event,
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey)
        )
    }

    private func matches(_ event: NSEvent, preset: SettingsStore.HotkeyPreset) -> Bool {
        matches(event, keyCode: preset.keyCode, carbonModifiers: preset.carbonModifiers)
    }

    private func matches(_ event: NSEvent, keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        guard event.type == .keyDown else { return false }
        guard UInt32(event.keyCode) == keyCode else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let wantsCommand = carbonModifiers & UInt32(cmdKey) != 0
        let wantsOption = carbonModifiers & UInt32(optionKey) != 0
        let wantsControl = carbonModifiers & UInt32(controlKey) != 0
        let wantsShift = carbonModifiers & UInt32(shiftKey) != 0

        return flags.contains(.command) == wantsCommand
            && flags.contains(.option) == wantsOption
            && flags.contains(.control) == wantsControl
            && flags.contains(.shift) == wantsShift
    }
}

extension Notification.Name {
    static let spotlightDidShow = Notification.Name("BetterSpotlight.didShow")
    static let spotlightWillHide = Notification.Name("BetterSpotlight.willHide")
    static let spotlightDidHide = Notification.Name("BetterSpotlight.didHide")
}
