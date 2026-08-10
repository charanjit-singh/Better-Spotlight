import AppKit
import SwiftUI

struct SearchView: View {
    let onDismiss: () -> Void

    @ObservedObject private var ui = LauncherUIModel.shared
    @State private var query = ""
    @State private var results: [AppEntry] = []
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var morphSpring: Animation {
        .spring(response: 0.38, dampingFraction: 0.84)
    }

    private var revealed: Bool { ui.isRevealed }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(spacing: 0) {
            searchField

            if !results.isEmpty {
                Divider()
                    .opacity(0.22)
                    .padding(.horizontal, 14)

                resultsList
            }
        }
        .frame(width: 600)
        // Solid material first so the UI is never an invisible glass ghost.
        .background(.ultraThinMaterial, in: shape)
        .glassEffect(.regular.interactive(), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        .scaleEffect(revealed ? 1.0 : 0.96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .animation(morphSpring, value: results.count)
        .animation(revealed ? morphSpring : .easeOut(duration: 0.08), value: revealed)
        .onAppear {
            reload(query: query)
            focusSearch()
        }
        .onChange(of: ui.showToken) { _, _ in
            query = ""
            selectedIndex = 0
            reload(query: "")
            focusSearch()
        }
        .onChange(of: ui.isRevealed) { _, isOn in
            if isOn {
                focusSearch()
            } else {
                isSearchFocused = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotlightDidHide)) { _ in
            query = ""
            results = []
            selectedIndex = 0
            isSearchFocused = false
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            withAnimation(morphSpring) {
                reload(query: newValue)
            }
        }
        .background(KeyEventHandler { key in
            handleKey(key)
        })
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .nonRepeating, value: revealed)

            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($isSearchFocused)
                .onSubmit { launchSelected() }

            if !query.isEmpty {
                Button {
                    withAnimation(morphSpring) { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                        AppRow(
                            app: app,
                            isSelected: index == selectedIndex
                        )
                        .id(app.id)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .move(edge: .top))
                                    .combined(with: .scale(scale: 0.98)),
                                removal: .opacity
                            )
                        )
                        .onTapGesture {
                            selectedIndex = index
                            launchSelected()
                        }
                        .onHover { hovering in
                            if hovering { selectedIndex = index }
                        }
                    }
                }
                .padding(10)
                .animation(morphSpring, value: results.map(\.id))
            }
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) { _, newValue in
                guard results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(results[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func reload(query: String) {
        results = AppIndexer.shared.search(query: query)
        if selectedIndex >= results.count {
            selectedIndex = max(results.count - 1, 0)
        }
    }

    private func focusSearch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func launchSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let app = results[selectedIndex]
        onDismiss()
        // Slight delay so the liquid dismiss can start before the app activates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AppIndexer.shared.launch(app)
        }
    }

    private func handleKey(_ key: KeyEventHandler.Key) {
        switch key {
        case .up:
            guard !results.isEmpty else { return }
            selectedIndex = max(selectedIndex - 1, 0)
        case .down:
            guard !results.isEmpty else { return }
            selectedIndex = min(selectedIndex + 1, results.count - 1)
        case .escape:
            onDismiss()
        case .return:
            launchSelected()
        }
    }
}

private struct AppRow: View {
    let app: AppEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIndexer.shared.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)

            Text(app.name)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Text("↩")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// Captures arrow / escape / return even while the text field is focused.
private struct KeyEventHandler: NSViewRepresentable {
    enum Key {
        case up, down, escape, `return`
    }

    let onKey: (Key) -> Void

    func makeNSView(context: Context) -> HandlerView {
        let view = HandlerView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: HandlerView, context: Context) {
        nsView.onKey = onKey
    }

    final class HandlerView: NSView {
        var onKey: ((Key) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                install()
            } else {
                remove()
            }
        }

        private func install() {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 126:
                    self.onKey?(.up)
                    return nil
                case 125:
                    self.onKey?(.down)
                    return nil
                case 53:
                    self.onKey?(.escape)
                    return nil
                case 36, 76:
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                        self.onKey?(.return)
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        }

        private func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            remove()
        }
    }
}

#Preview {
    SearchView(onDismiss: {})
        .frame(width: 640, height: 420)
        .preferredColorScheme(.dark)
}
