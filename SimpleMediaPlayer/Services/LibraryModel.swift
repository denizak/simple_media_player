import Foundation
import Observation

/// Remembers one music folder across launches and lists the audio files inside it.
@Observable
@MainActor
final class LibraryModel {
    private(set) var folderName: String?
    private(set) var tracks: [Track] = []
    private(set) var errorMessage: String?

    private static let bookmarkKey = "libraryFolderBookmark"

    #if os(macOS)
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    private var folderURL: URL?
    private var isAccessingFolder = false

    /// Re-opens the folder chosen in an earlier launch, if its bookmark still resolves.
    func restore() async {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: Self.resolveOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            await useFolder(url, saveBookmark: isStale)
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            errorMessage = "Couldn't reopen the last folder: \(error.localizedDescription)"
        }
    }

    func openFolder(_ url: URL) async {
        await useFolder(url, saveBookmark: true)
    }

    private func useFolder(_ url: URL, saveBookmark: Bool) async {
        if isAccessingFolder { folderURL?.stopAccessingSecurityScopedResource() }
        folderURL = url
        isAccessingFolder = url.startAccessingSecurityScopedResource()
        folderName = url.lastPathComponent
        errorMessage = nil

        if saveBookmark {
            do {
                let data = try url.bookmarkData(
                    options: Self.bookmarkOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            } catch {
                errorMessage = "Couldn't remember this folder: \(error.localizedDescription)"
            }
        }

        let files = await FolderScanner.audioFiles(in: url)
        tracks = files.map { Track(url: $0) }
    }
}
