import AVFoundation
import Accelerate
import Foundation

/// Live spectrum of the playing audio, split into log-spaced bands with levels from 0...1.
/// `process` runs on the audio thread, and `levels()` is read from the UI thread, so they share a lock.
final class SpectrumAnalyzer: @unchecked Sendable {
    static let bandCount = 40

    private let fftSize = 1024
    private let log2n: vDSP_Length = 10
    private let fftSetup: FFTSetup
    private let window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private let lock = NSLock()
    private var bandLevels = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imag = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func levels() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return bandLevels
    }

    func reset() {
        lock.lock()
        bandLevels = [Float](repeating: 0, count: Self.bandCount)
        lock.unlock()
    }

    /// Called on the audio thread with the mixed output.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], Int(buffer.frameLength) >= fftSize else { return }
        let sampleRate = buffer.format.sampleRate
        let half = fftSize / 2

        vDSP_vmul(channel, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let minFrequency = 40.0
        let maxFrequency = min(16_000.0, sampleRate / 2)
        let binHz = sampleRate / Double(fftSize)
        var newLevels = [Float](repeating: 0, count: Self.bandCount)

        for band in 0..<Self.bandCount {
            let lower = minFrequency * pow(maxFrequency / minFrequency, Double(band) / Double(Self.bandCount))
            let upper = minFrequency * pow(maxFrequency / minFrequency, Double(band + 1) / Double(Self.bandCount))
            let startBin = max(Int(lower / binHz), 1)
            let endBin = min(max(Int(upper / binHz), startBin + 1), half)
            var sum: Float = 0
            for bin in startBin..<endBin {
                sum += magnitudes[bin]
            }
            let average = sum / Float(endBin - startBin)
            // Map -60 dB...0 dB onto 0...1.
            let decibels = 20 * log10(max(average / Float(fftSize), 1e-6))
            newLevels[band] = min(max((decibels + 60) / 60, 0), 1)
        }

        lock.lock()
        for band in 0..<Self.bandCount {
            // Fall off slowly so the bars don't flicker.
            bandLevels[band] = max(newLevels[band], bandLevels[band] * 0.8)
        }
        lock.unlock()
    }
}

