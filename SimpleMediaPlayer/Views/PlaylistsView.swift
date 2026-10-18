import SwiftUI
import SwiftData

struct PlaylistsView: View {
    let engine: PlayerEngine

    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var isCreating = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist, engine: engine)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                        Text("\(playlist.entries.count) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Rename") {
                        renameText = playlist.name
                        renaming = playlist
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(playlists[index])
                }
                try? context.save()
            }
        }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Create a playlist, then add files to it.")
                )
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    isCreating = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $isCreating) {
            TextField("Name", text: $newName)
            Button("Create") { createPlaylist() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") { renamePlaylist() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    private func createPlaylist() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        context.insert(Playlist(name: name))
        try? context.save()
    }

    private func renamePlaylist() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let renaming, !name.isEmpty {
            renaming.name = name
            try? context.save()
        }
        renaming = nil
    }
}
