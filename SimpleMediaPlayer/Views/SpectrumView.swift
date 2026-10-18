import SwiftUI

/// Live spectrum bars. Reads the analyzer about 30 times a second while playing.
struct SpectrumView: View {
    let analyzer: SpectrumAnalyzer
    let isPlaying: Bool

    @State private var levels = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(levels.count)
            var path = Path()
            for (index, level) in levels.enumerated() {
                let height = max(CGFloat(level), 0.02) * size.height
                let rect = CGRect(
                    x: CGFloat(index) * step + 1,
                    y: size.height - height,
                    width: max(step - 2, 1),
                    height: height
                )
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
            }
            context.fill(path, with: .color(.accentColor))
        }
        .frame(height: 40)
        .accessibilityHidden(true)
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                levels = analyzer.levels()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}
