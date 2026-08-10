import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var indexer = AppIndexer.shared
    @State private var hotKeyStatus = PanelController.shared.hotKeyStatus
    @State private var loginStatus = LoginItemManager.statusDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.25)
            Form {
                Section("Startup") {
                    LabeledContent("Open at login") {
                        if LoginItemManager.isEnabled {
                            Text("On").foregroundStyle(.secondary)
                        } else {
                            Text("Required").foregroundStyle(Color.orange)
                        }
                    }
                    Text(loginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !LoginItemManager.isEnabled {
                        Button("Enable Open at Login") {
                            _ = LoginItemManager.ensureEnabled()
                            loginStatus = LoginItemManager.statusDescription
                        }
                    }
                }

                Section("Launcher Shortcut") {
                    ForEach(SettingsStore.presets) { preset in
                        presetRow(preset)

                        if preset.claimsSpotlight, settings.selectedPresetID == preset.id {
                            spotlightSetupGuide
                        }
                    }
                }

                Section("Appearance") {
                    Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    Text("Off by default. When disabled, use your hotkey to open the launcher. Double-click the app icon in Finder to open Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Apps") {
                    LabeledContent("Apps", value: "\(indexer.indexedCount)")
                    if let date = indexer.lastIndexedAt {
                        LabeledContent("Last refreshed", value: date.formatted(date: .abbreviated, time: .shortened))
                    }

                    if indexer.isIndexing {
                        ProgressView(value: indexer.indexProgress) {
                            Text("Refreshing… \(indexer.indexedCount) apps")
                                .font(.caption)
                        }
                    } else {
                        Button {
                            AppIndexer.shared.refresh()
                        } label: {
                            Label("Refresh Apps", systemImage: "arrow.clockwise")
                        }
                        Text("We keep a local list so the launcher stays quick. Refresh if you installed something new, or if an app won’t open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Better Spotlight")
                    LabeledContent("Version", value: settings.appVersion)
                    LabeledContent("Build", value: settings.buildNumber)
                    LabeledContent("Active shortcut", value: settings.selectedPreset.display)
                    LabeledContent("Hotkey status", value: hotKeyStatus)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 720)
        .onAppear {
            hotKeyStatus = PanelController.shared.hotKeyStatus
            loginStatus = LoginItemManager.statusDescription
            _ = LoginItemManager.ensureEnabled()
            loginStatus = LoginItemManager.statusDescription
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyRegistrationDidUpdate)) { note in
            if let message = note.object as? String {
                hotKeyStatus = message
            } else {
                hotKeyStatus = PanelController.shared.hotKeyStatus
            }
        }
    }

    private func presetRow(_ preset: SettingsStore.HotkeyPreset) -> some View {
        let isSelected = settings.selectedPresetID == preset.id

        return Button {
            settings.selectPreset(preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .foregroundStyle(.primary)
                    Text(preset.display)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if preset.claimsSpotlight {
                    Text("Overrides Spotlight")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var spotlightSetupGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("macOS keeps ⌘Space until you free it. Two quick steps:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GuideStep(
                number: 1,
                title: "Turn off Spotlight’s shortcut",
                detail: "Keyboard Settings → Keyboard Shortcuts → Spotlight → uncheck “Show Spotlight search”."
            )

            Button {
                SpotlightShortcutTakeover.disableSystemSpotlightShortcut()
                SpotlightShortcutTakeover.openKeyboardShortcutSettings()
            } label: {
                Label("Open Keyboard Settings", systemImage: "keyboard")
            }

            GuideStep(
                number: 2,
                title: "Allow Accessibility",
                detail: "Privacy & Security → Accessibility → enable Better Spotlight so it can capture ⌘Space."
            )

            Button {
                _ = SpotlightShortcutTakeover.ensureAccessibility(prompt: true)
                SpotlightShortcutTakeover.openAccessibilitySettings()
            } label: {
                Label("Open Accessibility Settings", systemImage: "hand.raised.fill")
            }

            HStack(spacing: 8) {
                Image(systemName: SpotlightShortcutTakeover.isAccessibilityTrusted
                      ? "checkmark.seal.fill"
                      : "exclamationmark.triangle.fill")
                    .foregroundStyle(SpotlightShortcutTakeover.isAccessibilityTrusted ? .green : .orange)

                Text(SpotlightShortcutTakeover.isAccessibilityTrusted
                     ? "Accessibility is enabled. Press ⌘Space to test."
                     : "Accessibility is not enabled yet. Finish step 2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 28)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Better Spotlight Settings")
                    .font(.title2.weight(.semibold))
                Text(settings.versionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }
}

private struct GuideStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.blue))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible {
            AppWindowPresentation.prepareToShowWindow()
            window.makeKeyAndOrderFront(nil)
            return
        }

        AppWindowPresentation.prepareToShowWindow()

        let view = SettingsView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Better Spotlight Settings"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 540, height: 760))
        window.minSize = NSSize(width: 480, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = SettingsWindowCloser.shared
        self.window = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    static func releaseWindow() {
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
    }
}

private final class SettingsWindowCloser: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowCloser()

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.releaseWindow()
        AppWindowPresentation.updateActivationPolicyForVisibleWindows()
    }
}
