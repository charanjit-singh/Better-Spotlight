import AppKit
import ApplicationServices

/// Disables macOS Spotlight's ⌘Space binding so Better Spotlight can own it.
enum SpotlightShortcutTakeover {
    /// Symbolic hotkey ID for "Show Spotlight search".
    private static let spotlightSearchID = "64"
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    /// Returns `true` when Spotlight's search hotkey is disabled (or was just disabled).
    @discardableResult
    static func disableSystemSpotlightShortcut() -> Bool {
        let existing = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
        var hotkeys = existing

        var entry = hotkeys[spotlightSearchID] as? [String: Any] ?? defaultSpotlightEntry()
        if let enabled = entry["enabled"] as? Bool, enabled == false {
            return true
        }

        entry["enabled"] = false
        if entry["value"] == nil {
            entry["value"] = defaultSpotlightEntry()["value"]!
        }
        hotkeys[spotlightSearchID] = entry

        CFPreferencesSetAppValue(key, hotkeys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)

        // Ask the system to reload symbolic hotkeys without a logout.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.apple.symbolichotkeys.changed" as CFString),
            nil,
            nil,
            true
        )

        return true
    }

    static func openKeyboardShortcutSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility if needed (required for the CGEvent-tap fallback).
    static func ensureAccessibility(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    private static func defaultSpotlightEntry() -> [String: Any] {
        [
            "enabled": false,
            "value": [
                "type": "standard",
                "parameters": [32, 49, 1_048_576], // Space, keyCode 49, ⌘
            ] as [String: Any],
        ]
    }
}
