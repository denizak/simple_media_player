import Foundation

struct Track: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}
