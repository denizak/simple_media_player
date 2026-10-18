import Foundation

/// Stores computed waveforms on disk so a file is decoded only once.
/// The key includes size and modification date, so an edited file is recomputed.
enum WaveformCache {
    private static let directory: URL? = {
        try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Waveforms", isDirectory: true)
    }()

    static func load(for url: URL, bucketCount: Int) -> [Float]? {
        guard let file = fileURL(for: url, bucketCount: bucketCount),
              let data = try? Data(contentsOf: file),
              data.count == bucketCount * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func save(_ samples: [Float], for url: URL, bucketCount: Int) {
        guard let file = fileURL(for: url, bucketCount: bucketCount) else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    private static func fileURL(for url: URL, bucketCount: Int) -> URL? {
        guard let directory else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(size)|\(Int(modified))|\(bucketCount)"
        return directory.appendingPathComponent("\(stableHash(key)).bin")
    }

    /// FNV-1a, so the file name stays the same across launches (Swift's `hashValue` is randomized per launch).
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
