import AVFoundation
import Accelerate

/// Decodes an audio file and reduces it to `bucketCount` loudness values (RMS, normalized to 0...1).
/// The stream yields partial results while decoding, so the waveform can fill in from left to right.
/// The last value yielded is the complete, final waveform.
/// A waveform snapshot. `loadedFraction` is how much of the file has been decoded (0...1).
struct WaveformUpdate: Sendable {
    let samples: [Float]
    let loadedFraction: Double
}

enum WaveformGenerator {
    private static let chunkFrames: AVAudioFrameCount = 65_536
    /// How many partial updates to send over the whole file.
    private static let updatesPerFile: Int64 = 60

    static func stream(for url: URL, bucketCount: Int) -> AsyncThrowingStream<WaveformUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try decode(url: url, bucketCount: bucketCount, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decode(
        url: URL,
        bucketCount: Int,
        continuation: AsyncThrowingStream<WaveformUpdate, Error>.Continuation
    ) throws {
        let file = try AVAudioFile(forReading: url)
        let totalFrames = file.length
        guard totalFrames > 0, bucketCount > 0 else {
            continuation.yield(WaveformUpdate(samples: [], loadedFraction: 1))
            return
        }

        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            continuation.yield(WaveformUpdate(samples: [], loadedFraction: 1))
            return
        }

        let total = Int64(totalFrames)
        let buckets = Int64(bucketCount)
        var sumSquares = [Float](repeating: 0, count: bucketCount)
        var sampleCounts = [Int](repeating: 0, count: bucketCount)
        var globalFrame: Int64 = 0
        let updateInterval = max(total / updatesPerFile, 1)
        var nextUpdate = updateInterval

        while file.framePosition < totalFrames {
            try Task.checkCancellation()
            try file.read(into: buffer)
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            guard let channels = buffer.floatChannelData else { break }

            // Walk the chunk bucket by bucket; a chunk can span several buckets or a bucket can span chunks.
            var start = 0
            while start < count {
                let frame = globalFrame + Int64(start)
                let bucket = min(Int(frame * buckets / total), bucketCount - 1)
                // First global frame that belongs to the next bucket.
                let nextBucketStart = (Int64(bucket + 1) * total + buckets - 1) / buckets
                let end = min(count, Int(nextBucketStart - globalFrame))
                let length = end - start

                var energy: Float = 0
                for channel in 0..<channelCount {
                    var partial: Float = 0
                    vDSP_svesq(channels[channel] + start, 1, &partial, vDSP_Length(length))
                    energy += partial
                }
                sumSquares[bucket] += energy
                sampleCounts[bucket] += length * channelCount
                start = end
            }
            globalFrame += Int64(count)

            if globalFrame >= nextUpdate {
                nextUpdate = globalFrame + updateInterval
                // Buckets that start before the decoded position have data; the rest are still empty.
                let filled = min(Int(globalFrame * buckets / total) + 1, bucketCount)
                continuation.yield(WaveformUpdate(
                    samples: snapshot(sumSquares, sampleCounts, filled: filled),
                    loadedFraction: Double(globalFrame) / Double(total)
                ))
            }
        }

        continuation.yield(WaveformUpdate(
            samples: snapshot(sumSquares, sampleCounts, filled: bucketCount),
            loadedFraction: 1
        ))
    }

    private static func snapshot(_ sumSquares: [Float], _ sampleCounts: [Int], filled: Int) -> [Float] {
        var rms = [Float](repeating: 0, count: sumSquares.count)
        for index in 0..<filled where sampleCounts[index] > 0 {
            rms[index] = (sumSquares[index] / Float(sampleCounts[index])).squareRoot()
        }
        guard let peak = rms.max(), peak > 0 else { return rms }
        return rms.map { $0 / peak }
    }
}
