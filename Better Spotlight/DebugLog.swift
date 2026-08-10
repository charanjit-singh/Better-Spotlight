import Foundation

enum DebugLog {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[BetterSpotlight] %@", message())
        #endif
    }
}
