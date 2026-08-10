import AppKit

@MainActor
enum AppWindowPresentation {
    static func prepareToShowWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Only hide from Dock again when nothing user-facing is left open.
    static func updateActivationPolicyForVisibleWindows() {
        DispatchQueue.main.async {
            let hasVisible = NSApp.windows.contains { $0.isVisible && !$0.isKind(of: NSPanel.self) }
            if hasVisible {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
