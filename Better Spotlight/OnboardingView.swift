import AppKit
import SwiftUI

/// First-run welcome: pitch, one-time app scan, then hand off to Settings.
struct OnboardingView: View {
    let onFinished: () -> Void

    @ObservedObject private var indexer = AppIndexer.shared
    @State private var step: Step = .intro
    @State private var didStartScan = false

    private enum Step: Int, CaseIterable {
        case intro
        case scan
        case finish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)

            Group {
                switch step {
                case .intro:
                    introPage
                case .scan:
                    scanPage
                case .finish:
                    finishPage
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .frame(width: 520, height: 500)
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Better Spotlight")
                    .font(.title2.weight(.semibold))
                Text("Search less. Open faster.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remember when search just opened your app?")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            quote

            Text("Spotlight now hands you web results, definitions, conversions and suggestions when all you wanted was Safari. Better Spotlight does the one thing: your apps, in the order you actually use them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Highlight(icon: "app.badge", text: "Apps only. Nothing else competing for the top result")
                Highlight(icon: "bolt.fill", text: "Learns your habits, so your favourites come first")
                Highlight(icon: "command", text: "Takes over ⌘Space if you want it to")
            }
        }
    }

    private var quote: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(.tint)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 6) {
                Text("“The greatest truths are the simplest things in the world, simple as your own existence.”")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)

                Text("Swami Vivekananda")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var scanPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(indexer.isIndexing ? "Gathering your apps" : "Your apps are ready")
                .font(.title3.weight(.semibold))

            Text("This happens once. Afterwards the launcher opens instantly, because we keep a small local list instead of searching your whole disk every time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: indexer.indexProgress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(indexer.indexedCount) apps found")
                    .monospacedDigit()
                Spacer()
                Text("\(Int(indexer.indexProgress * 100))%")
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: startScanIfNeeded)
    }

    private var finishPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(indexer.indexedCount) apps ready to go", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            Text("Two last things:")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Highlight(icon: "keyboard", text: "Pick your shortcut next. ⌥Space works right away. ⌘Space needs one tweak in System Settings")
                Highlight(icon: "power", text: "Better Spotlight starts with your Mac, so the shortcut is always there")
            }

            Text("You can reopen this welcome any time from Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ForEach(Step.allCases, id: \.rawValue) { dot in
                Circle()
                    .fill(dot == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }

            Spacer()

            if step == .finish {
                Button("Take Me to Shortcuts") { onFinished() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(primaryTitle) { advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(step == .scan && indexer.isIndexing)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var primaryTitle: String {
        switch step {
        case .intro:
            return "Get Started"
        case .scan:
            return indexer.isIndexing ? "Gathering…" : "Continue"
        case .finish:
            return "Take Me to Shortcuts"
        }
    }

    private func advance() {
        switch step {
        case .intro:
            step = .scan
        case .scan:
            step = .finish
        case .finish:
            onFinished()
        }
    }

    private func startScanIfNeeded() {
        guard !didStartScan else { return }
        didStartScan = true
        Task {
            await AppIndexer.shared.refreshAndWait()
        }
    }
}

private struct Highlight: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 18)

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
enum OnboardingWindowController {
    private static var window: NSWindow?

    static func show(onFinished: (() -> Void)? = nil) {
        if let window, window.isVisible {
            AppWindowPresentation.prepareToShowWindow()
            window.makeKeyAndOrderFront(nil)
            return
        }

        AppWindowPresentation.prepareToShowWindow()

        let view = OnboardingView {
            completeTransition(onFinished: onFinished)
        }
        presentWindow(rootView: view)
    }

    /// Settings opens first, then welcome closes. Avoids activation-policy flicker and double-release crashes.
    private static func completeTransition(onFinished: (() -> Void)?) {
        SettingsStore.shared.markOnboardingComplete()
        SettingsWindowController.show()
        onFinished?()
        closeWelcomeWindow()
    }

    private static func presentWindow(rootView: OnboardingView) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 520, height: 500))
        window.minSize = NSSize(width: 520, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = OnboardingWindowCloser.shared
        self.window = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func closeWelcomeWindow() {
        guard let existing = window else { return }
        window = nil
        existing.delegate = nil
        existing.close()
        AppWindowPresentation.updateActivationPolicyForVisibleWindows()
    }

    static func welcomeWindowWillClose() {
        window = nil
        AppWindowPresentation.updateActivationPolicyForVisibleWindows()
    }

    static func dismiss() {
        closeWelcomeWindow()
    }
}

private final class OnboardingWindowCloser: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowCloser()

    func windowWillClose(_ notification: Notification) {
        OnboardingWindowController.welcomeWindowWillClose()
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
