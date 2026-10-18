import SwiftUI
import SwiftData

@main
struct SimpleMediaPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Playlist.self, PlaylistEntry.self])
    }
}
