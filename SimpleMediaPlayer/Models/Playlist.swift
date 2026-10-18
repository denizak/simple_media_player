import Foundation
import SwiftData

@Model
final class Playlist {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    /// Entries in play order.
    var orderedEntries: [PlaylistEntry] {
        entries.sorted { $0.position < $1.position }
    }

    /// Appends files to the end of the playlist, remembering each one with a bookmark.
    func add(_ urls: [URL], to context: ModelContext) throws {
        var position = (entries.map(\.position).max() ?? -1) + 1
        for url in urls {
            let entry = PlaylistEntry(
                bookmark: try Bookmarks.make(for: url),
                fileName: url.lastPathComponent,
                position: position
            )
            entry.playlist = self
            context.insert(entry)
            position += 1
        }
        try context.save()
    }
}

@Model
final class PlaylistEntry {
    var bookmark: Data
    var fileName: String
    var position: Int
    var playlist: Playlist?

    init(bookmark: Data, fileName: String, position: Int) {
        self.bookmark = bookmark
        self.fileName = fileName
        self.position = position
    }
}
