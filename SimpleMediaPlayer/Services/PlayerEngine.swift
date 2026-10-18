import AVFoundation
import Observation

/// Frequencies of the 10 equalizer bands, in Hz.
let eqBandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

/// Plays a queue of tracks through AVAudioEngine, with a 10-band equalizer, and advances automatically.
@Observable
@MainActor
final class PlayerEngine {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var waveform: [Float] = []
    /// Gain in dB for each equalizer band, kept between launches.
    private(set) var gains: [Float]

    private static let gainsKey = "eqGains"

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: eqBandFrequencies.count)
    private var file: AVAudioFile?
    private var scopedURL: URL?
    /// Frame at which the current schedule starts; `playbackPosition` is measured from here.
    private var seekFrame: AVAudioFramePosition = 0
    private var hasSchedule = false
    /// Bumped whenever the schedule changes, so completion callbacks from old schedules are ignored.
    private var generation = 0
    private var ticker: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private let waveformGenerator = WaveformGenerator()

    var currentTrack: Track? {
        currentIndex.map { queue[$0] }
    }

    var title: String? {
        currentTrack?.title
    }

    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    var hasNext: Bool {
        (currentIndex ?? -1) + 1 < queue.count
    }

    init() {
        let saved = UserDefaults.standard.array(forKey: Self.gainsKey) as? [Float]
        gains = saved?.count == eqBandFrequencies.count
            ? saved!
            : Array(repeating: 0, count: eqBandFrequencies.count)

        audioEngine.attach(playerNode)
        audioEngine.attach(eqNode)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: nil)
        for (index, band) in eqNode.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = eqBandFrequencies[index]
            band.bandwidth = 1
            band.gain = gains[index]
            band.bypass = false
        }
    }

    /// Plays a single file as a queue of one.
    func load(_ url: URL) {
        play([Track(url: url)], at: 0)
    }

    func play(_ tracks: [Track], at index: Int) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        currentIndex = index
        loadCurrent(autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard file != nil else { return }
        do {
            if !audioEngine.isRunning {
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                try audioEngine.start()
            }
        } catch {
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
            return
        }
        if !hasSchedule {
            schedule(from: seekFrame)
        }
        playerNode.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        currentTime = playbackPosition()
        playerNode.pause()
        isPlaying = false
        stopTicker()
    }

    func next() {
        guard hasNext, let index = currentIndex else {
            stop()
            return
        }
        currentIndex = index + 1
        loadCurrent(autoplay: true)
    }

    /// Restarts the current track if it has played for a few seconds, otherwise goes to the previous one.
    func previous() {
        guard let index = currentIndex else { return }
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            currentIndex = index - 1
            loadCurrent(autoplay: true)
        }
    }

    func seek(to time: TimeInterval) {
        guard let file else { return }
        let clamped = min(max(time, 0), max(duration - 0.05, 0))
        currentTime = clamped
        schedule(from: AVAudioFramePosition(clamped * file.processingFormat.sampleRate))
        if isPlaying {
            playerNode.play()
        }
    }

    func seek(toFraction fraction: Double) {
        seek(to: fraction * duration)
    }

    func setGain(_ gain: Float, at index: Int) {
        guard gains.indices.contains(index) else { return }
        gains[index] = gain
        eqNode.bands[index].gain = gain
        UserDefaults.standard.set(gains, forKey: Self.gainsKey)
    }

    func applyPreset(_ presetGains: [Float]) {
        for (index, gain) in presetGains.enumerated() {
            setGain(gain, at: index)
        }
    }

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack else { return }
        unload()

        let isScoped = track.url.startAccessingSecurityScopedResource()
        do {
            let newFile = try AVAudioFile(forReading: track.url)
            file = newFile
            scopedURL = isScoped ? track.url : nil
            duration = Double(newFile.length) / newFile.processingFormat.sampleRate
            currentTime = 0
            errorMessage = nil

            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.connect(playerNode, to: eqNode, format: newFile.processingFormat)
            loadWaveform(from: track.url)
            if autoplay { resume() }
        } catch {
            if isScoped { track.url.stopAccessingSecurityScopedResource() }
            errorMessage = "Couldn't open \(track.title): \(error.localizedDescription)"
        }
    }

    /// Stops playback and clears the schedule, keeping the queue.
    private func stop() {
        unload()
        currentTime = 0
    }

    private func unload() {
        stopTicker()
        waveformTask?.cancel()
        waveformTask = nil
        waveform = []
        generation += 1
        playerNode.stop()
        hasSchedule = false
        seekFrame = 0
        file = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        isPlaying = false
    }

    /// Replaces the schedule with the rest of the file, starting at `frame`.
    private func schedule(from frame: AVAudioFramePosition) {
        guard let file else { return }
        generation += 1
        let token = generation
        playerNode.stop()
        seekFrame = frame

        let remaining = file.length - frame
        guard remaining > 0 else {
            hasSchedule = false
            return
        }
        hasSchedule = true
        playerNode.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                self?.segmentFinished(token)
            }
        }
    }

    private func segmentFinished(_ token: Int) {
        guard token == generation else { return }
        hasSchedule = false
        isPlaying = false
        stopTicker()
        next()
    }

    private func playbackPosition() -> TimeInterval {
        guard let file,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTime
        }
        let frame = seekFrame + playerTime.sampleTime
        return min(max(Double(frame) / file.processingFormat.sampleRate, 0), duration)
    }

    private func loadWaveform(from url: URL) {
        let generator = waveformGenerator
        let bucketCount = 1_000
        if let cached = WaveformCache.load(for: url, bucketCount: bucketCount) {
            waveform = cached
            return
        }
        waveformTask = Task {
            do {
                let samples = try await generator.samples(for: url, bucketCount: bucketCount)
                guard !Task.isCancelled else { return }
                WaveformCache.save(samples, for: url, bucketCount: bucketCount)
                self.waveform = samples
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Couldn't draw waveform: \(error.localizedDescription)"
            }
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentTime = self.playbackPosition()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
