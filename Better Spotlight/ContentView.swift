import SwiftUI

/// Kept for Xcode previews of the launcher chrome.
struct ContentView: View {
    var body: some View {
        SearchView(onDismiss: {})
            .frame(width: 640, height: 420)
    }
}

#Preview {
    ContentView()
}
