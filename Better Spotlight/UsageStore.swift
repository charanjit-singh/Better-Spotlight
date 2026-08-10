import Foundation

/// Persists per-app launch history and ranks by frecency (frequency × recency).
@MainActor
final class UsageStore {
    static let shared = UsageStore()

    struct Record: Codable, Sendable {
        var launchCount: Int
        var lastLaunchAt: Date
        /// Recent launch timestamps (capped) for smoother frecency.
        var recentLaunches: [Date]
    }

    private var records: [String: Record] = [:]
    private let fileURL: URL
    private let maxRecentLaunches = 40
    /// Half-life in days: a launch from this long ago contributes half as much.
    private let halfLifeDays: Double = 14

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Better Spotlight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("usage.json")
        load()
    }

    func recordLaunch(appID: String) {
        let now = Date()
        var record = records[appID] ?? Record(launchCount: 0, lastLaunchAt: now, recentLaunches: [])
        record.launchCount += 1
        record.lastLaunchAt = now
        record.recentLaunches.append(now)
        if record.recentLaunches.count > maxRecentLaunches {
            record.recentLaunches.removeFirst(record.recentLaunches.count - maxRecentLaunches)
        }
        records[appID] = record
        save()
    }

    /// Higher is better. Never-used apps score `0`.
    func score(for appID: String, now: Date = Date()) -> Double {
        guard let record = records[appID] else { return 0 }

        // Sum exponentially-decayed launch events (true frecency).
        var eventScore = 0.0
        for launch in record.recentLaunches {
            let days = max(now.timeIntervalSince(launch) / 86_400, 0)
            eventScore += pow(0.5, days / halfLifeDays)
        }

        // Stable floor from lifetime count so old favorites don't vanish entirely.
        let lifetimeBoost = log2(Double(record.launchCount) + 1.0)

        // Tiny recency nudge so two equally used apps prefer the fresher one.
        let hoursSince = max(now.timeIntervalSince(record.lastLaunchAt) / 3_600, 0)
        let recencyNudge = 1.0 / (1.0 + hoursSince / 24.0)

        return eventScore * 10.0 + lifetimeBoost + recencyNudge
    }

    func launchCount(for appID: String) -> Int {
        records[appID]?.launchCount ?? 0
    }

    func isFrequent(_ appID: String) -> Bool {
        launchCount(for: appID) > 0
    }

    func ranked(_ apps: [AppEntry]) -> [AppEntry] {
        apps.sorted { lhs, rhs in
            let ls = score(for: lhs.id)
            let rs = score(for: rhs.id)
            if ls != rs { return ls > rs }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Drop history for apps that are no longer installed / indexed.
    @discardableResult
    func prune(keeping validIDs: Set<String>) -> Int {
        let stale = records.keys.filter { !validIDs.contains($0) }
        guard !stale.isEmpty else { return 0 }
        for id in stale {
            records.removeValue(forKey: id)
        }
        save()
        return stale.count
    }

    /// Drop a single app's history (e.g. launch failed because it was deleted).
    func remove(appID: String) {
        guard records.removeValue(forKey: appID) != nil else { return }
        save()
    }

    /// Safety net: remove records whose `.app` bundle is gone from disk.
    @discardableResult
    func pruneMissingBundles() -> Int {
        let fm = FileManager.default
        let stale = records.keys.filter { !fm.fileExists(atPath: $0) }
        guard !stale.isEmpty else { return 0 }
        for id in stale {
            records.removeValue(forKey: id)
        }
        save()
        return stale.count
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
        // Clean tombstones left behind from previous uninstalls.
        _ = pruneMissingBundles()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
