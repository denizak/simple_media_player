import SwiftUI

private struct EQPreset {
    let name: String
    let gains: [Float]
}

private let eqPresets: [EQPreset] = [
    EQPreset(name: "Flat", gains: Array(repeating: 0, count: 10)),
    EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
    EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 3, 4, 5, 6]),
    EQPreset(name: "Vocal", gains: [-2, -2, -1, 1, 3, 3, 2, 1, 0, -1]),
    EQPreset(name: "Rock", gains: [4, 3, 1, -1, -2, -1, 1, 3, 4, 4]),
]

struct EqualizerView: View {
    let engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(eqPresets, id: \.name) { preset in
                        Button(preset.name) {
                            engine.applyPreset(preset.gains)
                        }
                    }
                }

                Section("Bands") {
                    ForEach(eqBandFrequencies.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Self.label(for: eqBandFrequencies[index]))
                                Spacer()
                                Text("\(Int(engine.gains[index])) dB")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(engine.gains[index]) },
                                    set: { engine.setGain(Float($0), at: index) }
                                ),
                                in: -12...12,
                                step: 1
                            )
                        }
                    }
                }
            }
            .navigationTitle("Equalizer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static func label(for frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000)) kHz" : "\(Int(frequency)) Hz"
    }
}
