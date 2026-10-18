# Simple Media Player

A small audio player for **iOS and macOS**, written in SwiftUI from a single multiplatform target. It uses only Apple system frameworks (AVFoundation, Accelerate, SwiftData, SwiftUI) and has no third-party dependencies.

## Features

- **Open a folder** and list the audio files in it, recursively, sorted by name. The folder is remembered across launches with a security-scoped bookmark.
- **Open a single file** from the file picker.
- **Playlists** (SwiftData): create, rename, and delete; add tracks from a folder through the context menu; reorder and remove entries; play from any entry. Files that have moved or been deleted appear greyed out as "File not found".
- **Waveform scrubber**: the whole track is drawn as bars, the played part is highlighted, and you tap or drag anywhere on it to seek. The waveform is decoded in the background, fills in from left to right, and is cached on disk, so a file is decoded only once.
- **Live spectrum**: 40 log-spaced bars computed with an FFT on the playing audio.
- **10-band equalizer** (AVAudioEngine + AVAudioUnitEQ) with presets: Flat, Bass Boost, Treble Boost, Vocal, Rock. Gains are remembered between launches.
- **Transport**: play/pause, previous (restarts the track after 3 s), next, and automatic advance to the next track.

## Requirements

- Xcode 27 or later
- iOS 17+ and macOS 14+

## Build and run

Open `SimpleMediaPlayer.xcodeproj` and run the `SimpleMediaPlayer` scheme on an iOS Simulator or on My Mac, or build from the command line:

```bash
xcodebuild -project SimpleMediaPlayer.xcodeproj -scheme SimpleMediaPlayer -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SimpleMediaPlayer.xcodeproj -scheme SimpleMediaPlayer -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

On iOS, files can be copied into the app's Documents folder through Finder or the Files app, because file sharing is enabled.

## Project layout

```
SimpleMediaPlayer/
├── SimpleMediaPlayerApp.swift     # @main, model container for playlists
├── RootView.swift                 # Folder list, playlists button, player bar
├── Info.plist                     # Background audio, file sharing
├── SimpleMediaPlayer.entitlements # App sandbox, read-only user-selected files, bookmarks
├── Models/
│   ├── Track.swift                # A file URL plus its display title
│   └── Playlist.swift             # SwiftData Playlist and PlaylistEntry (bookmark per file)
├── Services/
│   ├── PlayerEngine.swift         # Queue, AVAudioEngine playback, equalizer, seeking
│   ├── LibraryModel.swift         # Remembered folder and its tracks
│   ├── FolderScanner.swift        # Recursive scan for audio files
│   ├── Bookmarks.swift            # Security-scoped bookmark helpers
│   ├── WaveformGenerator.swift    # Streaming waveform decode (RMS, 1,000 bars)
│   ├── WaveformCache.swift        # On-disk waveform cache
│   └── SpectrumAnalyzer.swift     # FFT for the live spectrum
└── Views/
    ├── PlayerView.swift           # Waveform, spectrum, transport, equalizer button
    ├── WaveformScrubber.swift     # Waveform bars with tap/drag seeking
    ├── SpectrumView.swift         # Live spectrum bars
    ├── EqualizerView.swift        # Presets and band sliders
    ├── TrackListView.swift        # Tracks in the open folder
    ├── PlaylistsView.swift        # Playlist list
    └── PlaylistDetailView.swift   # Entries, reorder, delete, add files
```

## Not done yet

- Now Playing info and lock-screen or Control Center controls (`MediaPlayer`)
- macOS menu commands and keyboard shortcuts (Space to play, arrow keys to seek)
- Interruption and route-change handling on iOS (calls, unplugged headphones)
- Metadata (artist, artwork) and volume control
- Unit tests for the waveform, folder scanner, and queue logic
- A dedicated full-screen player on iPhone, and an app icon
