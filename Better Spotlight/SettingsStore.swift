import Carbon
import Combine
import Foundation

/// User-configurable launcher shortcut + related preferences.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    struct HotkeyPreset: Identifiable, Hashable {
        let id: String
        let title: String
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let claimsSpotlight: Bool

        var display: String {
            Self.symbolString(modifiers: carbonModifiers) + Self.keyName(keyCode: keyCode)
        }

        static func symbolString(modifiers: UInt32) -> String {
            var parts = ""
            if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
            return parts
        }

        static func keyName(keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_Space: return "Space"
            case kVK_Return: return "Return"
            case kVK_Tab: return "Tab"
            case kVK_Escape: return "Esc"
            default: return "Key"
            }
        }
    }

    static let presets: [HotkeyPreset] = [
        HotkeyPreset(
            id: "option-space",
            title: "Option + Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            claimsSpotlight: false
        ),
        HotkeyPreset(
            id: "command-space",
            title: "Command + Space (replace Spotlight)",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey),
            claimsSpotlight: true
        ),
        HotkeyPreset(
            id: "control-space",
            title: "Control + Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey),
            claimsSpotlight: false
        ),
        HotkeyPreset(
            id: "command-option-space",
            title: "Command + Option + Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey | optionKey),
            claimsSpotlight: false
        ),
    ]

    @Published private(set) var selectedPresetID: String {
        didSet { defaults.set(selectedPresetID, forKey: Keys.presetID) }
    }

    /// Menu bar icon — off by default.
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            NotificationCenter.default.post(name: .menuBarIconSettingDidChange, object: nil)
        }
    }

    /// First-run welcome + index flow.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Better Spotlight", isDirectory: true)
    }

    private static var forceWelcomeFlagURL: URL {
        supportDirectory.appendingPathComponent(".force-welcome")
    }

    static var shouldPresentWelcome: Bool {
        if FileManager.default.fileExists(atPath: forceWelcomeFlagURL.path) {
            return true
        }
        return !UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
    }

    static func consumeWelcomePresentationFlag() {
        try? FileManager.default.removeItem(at: forceWelcomeFlagURL)
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        Self.consumeWelcomePresentationFlag()
    }

    var selectedPreset: HotkeyPreset {
        Self.presets.first { $0.id == selectedPresetID } ?? Self.presets[0]
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var versionLabel: String {
        "Version \(appVersion) (\(buildNumber))"
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let presetID = "settings.hotkeyPresetID"
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    }

    private init() {
        let saved = defaults.string(forKey: Keys.presetID)
        if let saved, Self.presets.contains(where: { $0.id == saved }) {
            selectedPresetID = saved
        } else {
            selectedPresetID = Self.presets[0].id
        }
        // Default OFF unless the user has explicitly enabled it before.
        if defaults.object(forKey: Keys.showMenuBarIcon) == nil {
            showMenuBarIcon = false
        } else {
            showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        }
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func selectPreset(_ preset: HotkeyPreset) {
        selectedPresetID = preset.id
        if preset.claimsSpotlight {
            SpotlightShortcutTakeover.disableSystemSpotlightShortcut()
        }
        NotificationCenter.default.post(name: .hotkeySettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let hotkeySettingsDidChange = Notification.Name("BetterSpotlight.hotkeySettingsDidChange")
    static let hotkeyRegistrationDidUpdate = Notification.Name("BetterSpotlight.hotkeyRegistrationDidUpdate")
    static let menuBarIconSettingDidChange = Notification.Name("BetterSpotlight.menuBarIconSettingDidChange")
    static let openSettingsRequested = Notification.Name("BetterSpotlight.openSettingsRequested")
}
