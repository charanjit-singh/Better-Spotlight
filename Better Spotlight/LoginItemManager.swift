import Foundation
import ServiceManagement

/// Keeps Better Spotlight registered as a Login Item (required for hotkey agents).
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled. Opens when you log in"
        case .notRegistered:
            return "Not registered yet"
        case .notFound:
            return "Unavailable (install the app outside Xcode for login items)"
        case .requiresApproval:
            return "Waiting for approval in System Settings → Login Items"
        @unknown default:
            return "Unknown"
        }
    }

    /// Always attempt to register. Safe to call on every launch.
    @discardableResult
    static func ensureEnabled() -> Bool {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            return true
        }
        do {
            try service.register()
            DebugLog.log("login item registered")
            return service.status == .enabled
        } catch {
            DebugLog.log("login item register failed: \(error.localizedDescription)")
            return false
        }
    }
}
