import SwiftUI

/// SoundCloud-style waveform: bars left of the playhead are highlighted, and tapping or dragging seeks.
struct WaveformScrubber: View {
    let samples: [Float]
    let progress: Double
    @Binding var scrubFraction: Double?
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let playhead = scrubFraction ?? progress

            ZStack(alignment: .leading) {
                // Equatable, so these bars are only redrawn when the samples or width change, not on every playback tick.
                WaveformBars(samples: samples, color: Color.gray.opacity(0.5)).equatable()
                WaveformBars(samples: samples, color: .accentColor)
                    .equatable()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * playhead)
                    }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubFraction = Self.fraction(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        onSeek(Self.fraction(at: value.location.x, width: width))
                        scrubFraction = nil
                    }
            )
        }
        .frame(height: 80)
        .accessibilityElement()
        .accessibilityLabel("Seek")
        .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }
}

/// Draws all bars as one path, so each redraw is a single fill.
private struct WaveformBars: View, Equatable {
    let samples: [Float]
    let color: Color

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let step = barWidth + barGap
            let count = max(Int(size.width / step), 1)
            let bars = Self.resample(samples, to: count)

            var path = Path()
            for index in 0..<count {
                let x = CGFloat(index) * step
                let height = max(CGFloat(bars[index]), 0.04) * size.height
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
            }
            context.fill(path, with: .color(color))
        }
    }

    /// Reduces `samples` to `count` bars, keeping the peak of each group so short spikes stay visible.
    private static func resample(_ samples: [Float], to count: Int) -> [Float] {
        guard !samples.isEmpty else { return [Float](repeating: 0, count: count) }
        return (0..<count).map { index in
            let lower = index * samples.count / count
            let upper = min(max((index + 1) * samples.count / count, lower + 1), samples.count)
            return samples[lower..<upper].max() ?? 0
        }
    }
}

