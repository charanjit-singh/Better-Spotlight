import AppKit
import SwiftUI

struct SearchView: View {
    let onDismiss: () -> Void

    @ObservedObject private var ui = LauncherUIModel.shared
    @ObservedObject private var indexer = AppIndexer.shared
    @State private var query = ""
    @State private var results: [AppEntry] = []
    @State private var selectedIndex = 0
    @State private var acceptsHover = false
    @State private var shouldScrollToSelection = false
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
                    .opacity(0.28)
                    .padding(.horizontal, 14)

                resultsList
            }
        }
        .frame(width: 600)
        .background(shape.fill(.black.opacity(0.12)))
        .glassEffect(.regular, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1))
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
            acceptsHover = false
            shouldScrollToSelection = false
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
            shouldScrollToSelection = true
            withAnimation(morphSpring) {
                reload(query: newValue)
            }
        }
        .onChange(of: indexer.isIndexing) { _, isIndexing in
            if !isIndexing {
                reload(query: query)
            }
        }
        .background(MouseHoverGate(acceptsHover: $acceptsHover))
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

            Button {
                AppIndexer.shared.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(indexer.isIndexing ? 360 : 0))
                    .animation(
                        indexer.isIndexing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: indexer.isIndexing
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh Apps")
            .disabled(indexer.isIndexing)

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
                            guard acceptsHover, hovering else { return }
                            selectedIndex = index
                        }
                    }
                }
                .padding(10)
                .animation(morphSpring, value: results.map(\.id))
            }
            .frame(maxHeight: 320)
            .scrollIndicators(.never)
            .onChange(of: selectedIndex) { _, newValue in
                guard shouldScrollToSelection, results.indices.contains(newValue) else { return }
                shouldScrollToSelection = false
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
        if app.isRefresh {
            AppIndexer.shared.refresh()
            return
        }
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
            shouldScrollToSelection = true
            selectedIndex = max(selectedIndex - 1, 0)
        case .down:
            guard !results.isEmpty else { return }
            shouldScrollToSelection = true
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

/// Ignores hover until the cursor moves after the panel opens.
/// Prevents the list from jumping to wherever the mouse already sits.
private struct MouseHoverGate: NSViewRepresentable {
    @Binding var acceptsHover: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(acceptsHover: $acceptsHover)
    }

    func makeNSView(context: Context) -> GateView {
        let view = GateView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: GateView, context: Context) {
        context.coordinator.acceptsHover = $acceptsHover
        nsView.coordinator = context.coordinator
        context.coordinator.syncMonitoring(acceptsHover: acceptsHover)
    }

    static func dismantleNSView(_ nsView: GateView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class GateView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.syncMonitoring(acceptsHover: coordinator?.acceptsHover.wrappedValue ?? true)
        }
    }

    final class Coordinator {
        var acceptsHover: Binding<Bool>
        private var monitor: Any?
        private var anchor: CGPoint?

        init(acceptsHover: Binding<Bool>) {
            self.acceptsHover = acceptsHover
        }

        func syncMonitoring(acceptsHover: Bool) {
            if acceptsHover {
                stop()
            } else if monitor == nil {
                start()
            } else {
                anchor = NSEvent.mouseLocation
            }
        }

        func start() {
            guard monitor == nil else { return }
            anchor = NSEvent.mouseLocation
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                guard let self, !self.acceptsHover.wrappedValue, let anchor = self.anchor else { return event }
                let location = NSEvent.mouseLocation
                let dx = location.x - anchor.x
                let dy = location.y - anchor.y
                if (dx * dx + dy * dy) >= 9 {
                    self.acceptsHover.wrappedValue = true
                    self.stop()
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            anchor = nil
        }
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
