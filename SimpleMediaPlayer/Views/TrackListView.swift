import SwiftUI
import SwiftData

struct TrackListView: View {
    let tracks: [Track]
    let currentTrack: Track?
    let onSelect: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView(
                "No Audio Files",
                systemImage: "music.note.list",
                description: Text("Open a folder to list the audio files it contains.")
            )
        } else {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack {
                            Text(track.title)
                                .lineLimit(1)
                            Spacer()
                            if track == currentTrack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Menu("Add to Playlist") {
                            ForEach(playlists) { playlist in
                                Button(playlist.name) {
                                    try? playlist.add([track.url], to: context)
                                }
                            }
                            if playlists.isEmpty {
                                Text("No playlists yet")
                            }
                        }
                    }
                }
            }
        }
    }
}
