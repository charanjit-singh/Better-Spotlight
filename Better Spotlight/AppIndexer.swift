import AppKit
import Combine
import Foundation

struct AppEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL

    static let settingsID = "better-spotlight://settings"
    static let refreshID = "better-spotlight://refresh"

    static var settings: AppEntry {
        AppEntry(
            id: settingsID,
            name: "Better Spotlight Settings",
            url: URL(string: settingsID)!
        )
    }

    static var refresh: AppEntry {
        AppEntry(
            id: refreshID,
            name: "Refresh Apps",
            url: URL(string: refreshID)!
        )
    }

    var isSettings: Bool { id == Self.settingsID }
    var isRefresh: Bool { id == Self.refreshID }
    var isLauncherAction: Bool { isSettings || isRefresh }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Indexes installed `.app` bundles from standard Applications directories only.
/// Catalog is persisted so the launcher opens instantly after the first index.
@MainActor
final class AppIndexer: ObservableObject {
    static let shared = AppIndexer()

    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var indexProgress: Double = 0
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var lastIndexedAt: Date?

    /// Icons are the heavy part — keep few, purge when launcher hides.
    private var iconCache: [String: NSImage] = [:]
    private var refreshTask: Task<Void, Never>?
    private let catalogURL: URL

    private let searchRoots: [URL] = {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true),
        ]
        if let userApps = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(userApps)
        }
        return roots
    }()

    private var searchableApps: [AppEntry] {
        apps + [AppEntry.refresh, AppEntry.settings]
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Better Spotlight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        catalogURL = dir.appendingPathComponent("apps.json")
        loadFromDisk()
    }

    var hasCachedApps: Bool { !apps.isEmpty }

    /// Drop decoded app icons after the panel is dismissed.
    func purgeCaches() {
        iconCache.removeAll(keepingCapacity: false)
    }

    /// Full rescan (onboarding, Settings button, missing-app recovery).
    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
            self.refreshTask = nil
        }
    }

    func refreshAndWait() async {
        if let existing = refreshTask {
            await existing.value
            return
        }
        refresh()
        await refreshTask?.value
    }

    private func performRefresh() async {
        isIndexing = true
        indexProgress = 0
        indexedCount = apps.count

        let roots = searchRoots
        let scanned = await Task.detached(priority: .userInitiated) {
            Self.scan(roots: roots) { progress, count in
                Task { @MainActor in
                    AppIndexer.shared.indexProgress = progress
                    AppIndexer.shared.indexedCount = count
                }
            }
        }.value

        guard !Task.isCancelled else {
            isIndexing = false
            return
        }

        apps = scanned
        indexedCount = scanned.count
        indexProgress = 1
        lastIndexedAt = Date()
        persistToDisk()

        var validIDs = Set(scanned.map(\.id))
        validIDs.insert(AppEntry.settingsID)
        validIDs.insert(AppEntry.refreshID)
        UsageStore.shared.prune(keeping: validIDs)
        iconCache = iconCache.filter { validIDs.contains($0.key) }

        isIndexing = false
        DebugLog.log("index complete count=\(scanned.count)")
    }

    func search(query: String, limit: Int = 12) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let usage = UsageStore.shared
        let catalog = searchableApps

        guard !trimmed.isEmpty else {
            var ranked = Array(usage.ranked(apps).prefix(max(limit - 2, 0)))
            ranked.append(AppEntry.refresh)
            ranked.append(AppEntry.settings)
            return ranked
        }

        let lower = trimmed.lowercased()
        var prefix: [AppEntry] = []
        var contains: [AppEntry] = []

        for app in catalog {
            let name = app.name.lowercased()
            if name.hasPrefix(lower) {
                prefix.append(app)
            } else if name.contains(lower) {
                contains.append(app)
            }
        }

        let ordered = usage.ranked(prefix) + usage.ranked(contains)
        return Array(ordered.prefix(limit))
    }

    func icon(for app: AppEntry) -> NSImage {
        if let cached = iconCache[app.id] { return cached }

        let image: NSImage
        if app.isRefresh,
           let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
            image = symbol
        } else if app.isSettings, let logo = NSImage(named: "AppLogo") {
            image = logo
        } else if app.isSettings {
            image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        } else {
            image = NSWorkspace.shared.icon(forFile: app.url.path)
        }
        let target = NSSize(width: 32, height: 32)
        let tiny = NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        if iconCache.count > 40 {
            iconCache.removeAll(keepingCapacity: false)
        }
        iconCache[app.id] = tiny
        return tiny
    }

    func launch(_ app: AppEntry) {
        if app.isRefresh {
            refresh()
            return
        }

        if app.isSettings {
            PanelController.shared.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                SettingsWindowController.show()
            }
            return
        }

        guard FileManager.default.fileExists(atPath: app.id) else {
            handleMissingApp(app)
            return
        }

        UsageStore.shared.recordLaunch(appID: app.id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if error != nil {
                Task { @MainActor in
                    if !FileManager.default.fileExists(atPath: app.id) {
                        self.handleMissingApp(app)
                    }
                }
            }
        }
    }

    private func handleMissingApp(_ app: AppEntry) {
        DebugLog.log("missing app → reindex id=\(app.id)")
        UsageStore.shared.remove(appID: app.id)
        apps.removeAll { $0.id == app.id }
        iconCache.removeValue(forKey: app.id)
        persistToDisk()
        refresh()
    }

    // MARK: - Persistence

    private struct CachedApp: Codable {
        var id: String
        var name: String
        var path: String
    }

    private struct CachedCatalog: Codable {
        var apps: [CachedApp]
        var savedAt: Date
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: catalogURL),
              let cached = try? JSONDecoder().decode(CachedCatalog.self, from: data)
        else { return }

        let fm = FileManager.default
        let living = cached.apps.compactMap { item -> AppEntry? in
            guard fm.fileExists(atPath: item.path) else { return nil }
            return AppEntry(id: item.id, name: item.name, url: URL(fileURLWithPath: item.path))
        }
        apps = living.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        indexedCount = apps.count
        lastIndexedAt = cached.savedAt
        DebugLog.log("loaded cached apps count=\(apps.count)")
    }

    private func persistToDisk() {
        let payload = CachedCatalog(
            apps: apps.map { CachedApp(id: $0.id, name: $0.name, path: $0.url.path) },
            savedAt: lastIndexedAt ?? Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: catalogURL, options: [.atomic])
    }

    // MARK: - Scan (background)

    nonisolated private static func scan(
        roots: [URL],
        progress: @escaping @Sendable (Double, Int) -> Void
    ) -> [AppEntry] {
        var discovered: [String: AppEntry] = [:]
        let fm = FileManager.default
        let totalRoots = max(roots.count, 1)

        for (rootIndex, root) in roots.enumerated() {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                progress(Double(rootIndex + 1) / Double(totalRoots), discovered.count)
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension == "app" else { continue }

                let relative = item.path.replacingOccurrences(of: root.path, with: "")
                let nestedDepth = relative.split(separator: "/").filter { $0.hasSuffix(".app") }.count
                if nestedDepth > 1 {
                    enumerator.skipDescendants()
                    continue
                }

                enumerator.skipDescendants()

                let name = item.deletingPathExtension().lastPathComponent
                let id = item.standardizedFileURL.path
                if discovered[id] == nil {
                    discovered[id] = AppEntry(id: id, name: name, url: item.standardizedFileURL)
                    if discovered.count % 12 == 0 {
                        let base = Double(rootIndex) / Double(totalRoots)
                        let step = 1.0 / Double(totalRoots)
                        // Soft intra-root progress — capped so we don't claim 100% early.
                        progress(min(base + step * 0.85, 0.99), discovered.count)
                    }
                }
            }

            progress(Double(rootIndex + 1) / Double(totalRoots), discovered.count)
        }

        progress(1, discovered.count)
        return discovered.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
