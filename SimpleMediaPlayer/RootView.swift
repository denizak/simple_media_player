import SwiftUI

struct RootView: View {
    @State private var engine = PlayerEngine()
    @State private var library = LibraryModel()
    @State private var isPickingFolder = false
    @State private var isPickingFile = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                TrackListView(
                    tracks: library.tracks,
                    currentTrack: engine.currentTrack,
                    onSelect: { index in engine.play(library.tracks, at: index) }
                )
                .navigationTitle(library.folderName ?? "Simple Media Player")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        NavigationLink {
                            PlaylistsView(engine: engine)
                        } label: {
                            Label("Playlists", systemImage: "music.note.list")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Open Folder…") { isPickingFolder = true }
                            Button("Open File…") { isPickingFile = true }
                        } label: {
                            Label("Open", systemImage: "folder")
                        }
                    }
                }
            }

            // Outside the navigation stack, so it stays visible on pushed screens such as playlists.
            PlayerView(engine: engine)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .task {
            await library.restore()
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await library.openFolder(url) }
            }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                engine.load(url)
            }
        }
    }
}

#Preview {
    RootView()
}
