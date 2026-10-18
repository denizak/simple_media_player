import SwiftUI

struct PlayerView: View {
    let engine: PlayerEngine
    /// Fraction (0...1) while the user is dragging on the waveform; nil when not scrubbing.
    @State private var scrubFraction: Double?
    @State private var isShowingEqualizer = false

    private var displayedTime: TimeInterval {
        (scrubFraction ?? engine.progress) * engine.duration
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(engine.title ?? "Nothing playing")
                .font(.headline)
                .lineLimit(1)

            VStack(spacing: 4) {
                WaveformScrubber(
                    samples: engine.waveform,
                    loaded: engine.waveformLoaded,
                    progress: engine.progress,
                    scrubFraction: $scrubFraction,
                    onSeek: { engine.seek(toFraction: $0) }
                )

                HStack {
                    Text(Self.format(displayedTime))
                    Spacer()
                    Text("-" + Self.format(max(engine.duration - displayedTime, 0)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .disabled(engine.currentTrack == nil)

            SpectrumView(analyzer: engine.spectrum, isPlaying: engine.isPlaying)

            HStack(spacing: 40) {
                Button {
                    engine.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(engine.currentIndex == nil)

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .disabled(engine.currentTrack == nil)

                Button {
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(!engine.hasNext)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button {
                    isShowingEqualizer = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            if let message = engine.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .sheet(isPresented: $isShowingEqualizer) {
            EqualizerView(engine: engine)
        }
    }

    private static func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
