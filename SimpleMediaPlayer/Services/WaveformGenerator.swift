import AVFoundation
import Accelerate

/// Decodes an audio file once and reduces it to `bucketCount` loudness values (RMS, normalized to 0...1).
actor WaveformGenerator {
    private let chunkFrames: AVAudioFrameCount = 65_536

    func samples(for url: URL, bucketCount: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let totalFrames = file.length
        guard totalFrames > 0, bucketCount > 0 else { return [] }

        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return [] }

        let total = Int64(totalFrames)
        let buckets = Int64(bucketCount)
        var sumSquares = [Float](repeating: 0, count: bucketCount)
        var sampleCounts = [Int](repeating: 0, count: bucketCount)
        var globalFrame: Int64 = 0

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
        }

        var rms = [Float](repeating: 0, count: bucketCount)
        for index in 0..<bucketCount where sampleCounts[index] > 0 {
            rms[index] = (sumSquares[index] / Float(sampleCounts[index])).squareRoot()
        }
        guard let peak = rms.max(), peak > 0 else { return rms }
        return rms.map { $0 / peak }
    }
}
