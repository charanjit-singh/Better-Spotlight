import Combine
import Foundation

/// Shared presentation state so the panel never depends on NotificationCenter races.
@MainActor
final class LauncherUIModel: ObservableObject {
    static let shared = LauncherUIModel()

    /// Bumped on every show so SearchView can reset query/results.
    @Published private(set) var showToken: Int = 0
    @Published var isRevealed: Bool = false

    func beginShow() {
        showToken &+= 1
        // Stay revealed — never flash opacity 0 while the panel is on-screen.
        isRevealed = true
    }

    func beginHide() {
        isRevealed = false
    }
}
