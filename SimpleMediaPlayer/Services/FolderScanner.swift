import Foundation

/// Finds audio files inside a folder, recursively, sorted by file name.
enum FolderScanner {
    static func audioFiles(in folder: URL) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            collectAudioFiles(in: folder)
        }.value
    }

    private static func collectAudioFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let type = values.contentType,
                  type.conforms(to: .audio) else { continue }
            files.append(url)
        }
        return files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
