# Simple Media Player — Plan

A native audio player for **iOS and macOS** from one codebase. It uses only Apple system frameworks and adds **no third‑party dependencies**.

## 1. Goals and scope

**v1 (this plan)**
- Play local audio files (mp3, m4a/aac, wav, aiff, flac, alac, caf: whatever AVFoundation decodes).
- Pick a **folder** and list the audio files in it, or build a **playlist** from files chosen by hand.
- A **waveform scrubber** like SoundCloud's: the whole track is drawn as bars, the part already played is colored, and you tap or drag anywhere on it to seek.
- Standard transport: play/pause, previous/next, elapsed and remaining time, volume (macOS).
- System integration: background audio (iOS), Now Playing / Control Center / lock screen / media keys, AirPods controls.

**Out of scope for v1:** video, streaming URLs, tag editing, an equalizer, iCloud sync of playlists, tvOS/watchOS.

## 2. Platform and tech choices

| Concern | Choice | Why |
|---|---|---|
| Targets | One **multiplatform SwiftUI app target** (iOS 17+, macOS 14+) | One codebase. `@Observable` and `NavigationSplitView` work on both. |
| Language | Swift 6, strict concurrency | Safe threading for decoding the waveform in the background |
| Playback | `AVAudioPlayer` | Built in, low overhead, has `currentTime` for seeking and supports every system codec. `AVPlayer` would only matter for streaming, which is out of scope. |
| Waveform data | `AVAudioFile` + `AVAudioPCMBuffer` (AVFoundation) and `Accelerate`/vDSP for the RMS/peak downsampling | Both are system frameworks. vDSP keeps decoding fast. |
| Waveform drawing | SwiftUI `Canvas` | Fast and works on both platforms |
| File access | `.fileImporter` (folders and files) + **security‑scoped bookmarks** | Required by the sandbox on both OSes. Bookmarks keep access across launches. |
| Persistence | `SwiftData` (playlists, folder bookmarks, cached waveforms) | A system framework, so it adds no dependency. Plain JSON files in Application Support would also work. |
| Metadata | `AVURLAsset.load(.commonMetadata, .duration)` | Gives title, artist, artwork and duration |
| System controls | `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) | Works on both iOS and macOS |

> "Spectrum" here means the **amplitude waveform** (what SoundCloud shows). A real frequency spectrum (an FFT spectrogram) is listed as an optional later feature in §9.

## 3. Architecture

```
SimpleMediaPlayer/
├── App/
│   ├── SimpleMediaPlayerApp.swift      # @main, scenes, model container, menu commands (macOS)
│   └── AudioSessionConfigurator.swift  # iOS-only AVAudioSession setup (#if os(iOS))
├── Models/
│   ├── Track.swift                     # id, bookmark/url, title, artist, duration, artwork
│   ├── Playlist.swift                  # @Model: name, ordered track refs
│   ├── LibraryFolder.swift             # @Model: bookmark data, display name
│   └── WaveformCache.swift             # @Model: file key (path+size+mtime) → [Float] samples
├── Services/
│   ├── PlayerEngine.swift              # @Observable @MainActor; wraps AVAudioPlayer, queue, time ticker
│   ├── WaveformGenerator.swift         # actor; decode → downsample → normalize, cancellable
│   ├── FolderScanner.swift             # enumerate a folder, filter by UTType.audio
│   ├── BookmarkStore.swift             # create/resolve security-scoped bookmarks, stale handling
│   ├── MetadataLoader.swift            # async AVURLAsset metadata
│   └── NowPlayingController.swift      # MPNowPlayingInfoCenter + MPRemoteCommandCenter
├── Views/
│   ├── RootView.swift                  # NavigationSplitView: sidebar | track list | (player)
│   ├── SidebarView.swift               # Folders section, Playlists section, "+" actions
│   ├── TrackListView.swift             # list of tracks, tap to play, context menu "Add to playlist"
│   ├── PlayerBar.swift                 # compact bar: artwork, title, play/pause, mini waveform
│   ├── NowPlayingView.swift            # full player (sheet on iOS, inspector/bottom pane on macOS)
│   ├── WaveformScrubber.swift          # Canvas bars + gesture-based seeking
│   └── TransportControls.swift
└── Resources/  Assets.xcassets, Info.plist entries, entitlements
SimpleMediaPlayerTests/
    WaveformGeneratorTests.swift, FolderScannerTests.swift, PlayerEngineTests.swift
```

How data flows: the UI calls `PlayerEngine.play(track:in:queue)`. The engine resolves the file and starts security‑scoped access, creates the `AVAudioPlayer`, publishes `currentTime`, `duration` and `isPlaying`, and asks `WaveformGenerator` for samples (from the cache, or computed in the background). `WaveformScrubber` draws the samples and `progress = currentTime / duration`. When the user seeks, it calls `engine.seek(to:)`.

## 4. Feature details

### 4.1 Folder browsing
1. "Add Folder" → `.fileImporter(allowedContentTypes: [.folder])`.
2. Save a security‑scoped bookmark (on macOS `.withSecurityScope`; on iOS the bookmark keeps access to the folder picked in the Files app).
3. `FolderScanner` enumerates with `FileManager.enumerator(at:includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey])` and keeps files whose `UTType` conforms to `.audio`. Option: recursive or top level only (default: recursive).
4. Results are sorted by filename (natural sort with `localizedStandardCompare`). Metadata loads lazily per row.
5. A Refresh button rescans. Optional later: watch the folder with `NSFilePresenter`.

### 4.2 Playlists
- Create, rename, delete. Add tracks from a folder list (context menu or swipe) or "Add Files…" (`.fileImporter`, multiple selection, `.audio`).
- Each entry stores a **per‑file bookmark**, so the playlist still works if the folder is never added.
- Reorder with `.onMove` and remove with `.onDelete`.
- Missing or unresolvable files appear greyed out and are skipped during playback.

### 4.3 Playback engine (`PlayerEngine`)
- State: `queue: [Track]`, `currentIndex`, `isPlaying`, `currentTime`, `duration`, `repeatMode`, `shuffle`, `volume`.
- Time updates come from a ~30 Hz timer (or `TimelineView` in the view) that reads `player.currentTime` while playing.
- When a track finishes (`AVAudioPlayerDelegate.audioPlayerDidFinishPlaying`), the next one in the queue plays, following the repeat and shuffle settings.
- Previous: if more than 3 s have played, restart the track; otherwise go to the previous one.
- Errors (decode failure, missing file) raise a non‑blocking alert and skip to the next track.
- iOS only: `AVAudioSession` category `.playback`, `UIBackgroundModes: audio`, and handlers for interruptions (calls) and route changes (pause when headphones are unplugged).

### 4.4 Waveform scrubber (the key feature)
**Generation (`WaveformGenerator`, an actor):**
1. Open `AVAudioFile` and read it in chunks (e.g. 64k frames) into `AVAudioPCMBuffer` (float, non‑interleaved).
2. Mix the channels down to mono, then split the file into **N buckets** (N ≈ 1,000; the view resamples to its bar count). For each bucket, compute RMS (with `vDSP_rmsqv`), or peak (`vDSP_maxmgv`) for a spikier SoundCloud look.
3. Normalize to 0…1. Optionally apply light gamma or log scaling so quiet passages stay visible.
4. Report partial results so the waveform "fills in" while decoding. Support `Task` cancellation when the track changes.
5. Cache the result in `WaveformCache`, keyed by file identity (path + size + modification date). A 1,000‑float array is about 4 KB.

**Rendering (`WaveformScrubber`, SwiftUI `Canvas`):**
- Bar count = `width / (barWidth + gap)` (e.g. 2 pt bar + 1 pt gap). The samples are resampled to that count.
- Bars are mirrored around the center line (or bottom‑aligned like SoundCloud, with a faint reflection).
- Bars before `progress` use the accent color; bars after it use secondary grey. While dragging, a lighter "hover/scrub preview" color appears, plus a time tooltip.
- Placeholder: animated flat bars until the samples arrive.

**Interaction:**
- `DragGesture(minimumDistance: 0)`: a tap seeks right away. A drag shows the preview position and **seeks on release**, which avoids audio stutter (with optional live seeking).
- macOS: `onContinuousHover` shows a hover line and time. Arrow keys seek ±5 s, Space plays/pauses.
- Accessibility: `.accessibilityElement` + `.accessibilityValue("1:23 of 4:05")` + `.accessibilityAdjustableAction` (±5 s).

### 4.5 System integration
- `NowPlayingController` updates title, artist, artwork, duration, elapsed time and playback rate, and handles play, pause, toggle, next, previous and `changePlaybackPosition` (so the lock screen scrubber works).
- macOS: menu bar commands (`.commands`) for Play/Pause (Space), Next (⌘→), Previous (⌘←). Media keys work through `MPRemoteCommandCenter`.

## 5. UI layout
- **macOS:** three columns. The sidebar holds Folders and Playlists, the middle shows tracks, and a **bottom player bar** spans the window with a large waveform scrubber. Window minimum is about 800×500.
- **iPad:** the same split view.
- **iPhone:** `NavigationStack` (sidebar → track list). A mini player bar sits above the safe area. Tapping it opens a full‑screen `NowPlayingView` with artwork, a large waveform and transport controls.

## 6. Project setup
- Xcode project: a **Multiplatform App** template, product `SimpleMediaPlayer`, bundle id `com.<you>.SimpleMediaPlayer`.
- Capabilities:
  - macOS: App Sandbox, *User Selected File: Read Only*, plus app‑scope bookmarks (`com.apple.security.files.bookmarks.app-scope`).
  - iOS: Background Modes → *Audio, AirPlay, and Picture in Picture*. Optionally `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`, so files can be dropped into the app's Documents folder through Finder or the Files app.
- No Swift packages and no CocoaPods.
- Optionally use **XcodeGen‑free** hand‑written `.xcodeproj` generation. Simplest is to let Xcode create the project, or to create it with `xcodebuild`‑compatible files that I generate.

## 7. Implementation milestones
1. **Skeleton:** the multiplatform project, entitlements, and an empty `RootView` that builds and runs on the iOS Simulator and on macOS.
2. **Playback MVP:** pick a single file, play/pause, a plain `Slider` for seeking, and the time labels.
3. **Folder browsing:** bookmarks, scanner, track list with metadata, queue from the folder, next/previous, auto‑advance.
4. **Waveform:** generator + cache + `Canvas` scrubber that replaces the slider. Tests for bucket math and normalization.
5. **Playlists:** SwiftData models, CRUD, add from list or files, reorder, persistence across launches.
6. **System integration:** audio session, background playback, Now Playing, remote commands, macOS menu commands and keyboard shortcuts.
7. **Polish:** iPhone full‑screen player, empty states, error handling, accessibility, dark mode, app icon.

Every milestone ends with a build of both platforms (`xcodebuild -scheme SimpleMediaPlayer -destination 'platform=iOS Simulator,…'` and `'platform=macOS'`) and a manual check in the Simulator and on the Mac.

## 8. Testing
- **Unit:** `WaveformGenerator` on generated sine/silence WAV fixtures (expected bucket count, normalization, silence → ~0). `FolderScanner` filtering. `PlayerEngine` queue logic (next/prev/repeat/shuffle), with the player behind a small protocol.
- **Manual matrix:** mp3, m4a, wav and flac. Long files (1 h+) for waveform speed, which should stay under ~1–2 s with vDSP. Files that went missing after a bookmark was saved. Headphone unplug and phone‑call interruption on iOS.

## 9. Possible later features
- True **frequency spectrum** or spectrogram view (vDSP FFT), and a live visualizer through `AVAudioEngine` taps.
- Video playback (`AVPlayer` + `VideoPlayer`), which fits the "media player" name.
- Playback speed, gapless playback (via `AVAudioEngine` / `AVQueuePlayer`), search, sorting by tag.

## 10. Risks and open questions
- **iOS file access:** iOS has no general filesystem. Folders must come from the Files app (On My iPhone, iCloud Drive or external drives), and the bookmark must be resolved and `startAccessingSecurityScopedResource()` called on every launch. This is handled in `BookmarkStore`.
- **Waveform for very long files:** decoding is linear in file length. Mitigations are the cache, progressive output, and bucketed reading.
- **Open questions for you:**
  1. Minimum OS: is **iOS 17 / macOS 14** OK? This choice enables `@Observable` and SwiftData.
  2. Should the folder scan be recursive by default?
  3. Waveform style: SoundCloud‑style bottom‑aligned bars, or bars mirrored around the center?
