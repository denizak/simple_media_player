import SwiftUI

/// SoundCloud-style waveform: bars left of the playhead are highlighted, and tapping or dragging seeks.
struct WaveformScrubber: View {
    let samples: [Float]
    let progress: Double
    @Binding var scrubFraction: Double?
    let onSeek: (Double) -> Void

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let playhead = scrubFraction ?? progress

            Canvas { context, size in
                let step = barWidth + barGap
                let count = max(Int(size.width / step), 1)
                let bars = Self.resample(samples, to: count)
                let playheadX = size.width * playhead

                for index in 0..<count {
                    let x = CGFloat(index) * step
                    let amplitude = max(CGFloat(bars[index]), 0.04)
                    let height = amplitude * size.height
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let color: Color = x + barWidth <= playheadX ? .accentColor : Color.gray.opacity(0.5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
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
