import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    let playlist: Playlist
    let engine: PlayerEngine

    @Environment(\.modelContext) private var context
    @State private var isAddingFiles = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(playlist.orderedEntries) { entry in
                row(for: entry)
            }
            .onDelete { offsets in
                let entries = playlist.orderedEntries
                for index in offsets {
                    context.delete(entries[index])
                }
                try? context.save()
            }
            .onMove { from, to in
                var entries = playlist.orderedEntries
                entries.move(fromOffsets: from, toOffset: to)
                for (index, entry) in entries.enumerated() {
                    entry.position = index
                }
                try? context.save()
            }
        }
        .overlay {
            if playlist.entries.isEmpty {
                ContentUnavailableView(
                    "Empty Playlist",
                    systemImage: "music.note",
                    description: Text("Add audio files to this playlist.")
                )
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingFiles = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
            }
            #endif
        }
        .fileImporter(
            isPresented: $isAddingFiles,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                do {
                    try playlist.add(urls, to: context)
                } catch {
                    errorMessage = "Couldn't add files: \(error.localizedDescription)"
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: PlaylistEntry) -> some View {
        if let url = Bookmarks.resolve(entry.bookmark) {
            Button {
                play(entry, url: url)
            } label: {
                HStack {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    if engine.currentTrack?.url == url {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .lineLimit(1)
                Text("File not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Queues every playable entry, starting at the one that was tapped. Missing files are skipped.
    private func play(_ entry: PlaylistEntry, url: URL) {
        let urls = playlist.orderedEntries.compactMap { Bookmarks.resolve($0.bookmark) }
        let tracks = urls.map { Track(url: $0) }
        guard let index = urls.firstIndex(of: url) else { return }
        engine.play(tracks, at: index)
    }
}
