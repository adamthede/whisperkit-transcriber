# Implementation Plan: Video File Support with Inline Player

## Overview
Add support for transcribing video files by extracting audio tracks, and provide an inline video player with subtitle synchronization and playback speed controls. This expands the use case from audio-only to video content transcription.

## Current State
- **Audio only**: Supports WAV, MP3, M4A, AAC, FLAC, OGG, WMA
- **No video support**: Video files are not recognized or processed
- **No playback**: No way to preview audio/video content
- **No subtitle sync**: No way to view transcriptions synchronized with playback

## Technical Approach

### Phase 1: Video File Support
1. Extend file type detection to include video formats
2. Extract audio from video files using AVFoundation
3. Transcribe extracted audio (reuse existing transcription logic)

### Phase 2: Video Player Integration
1. Add AVPlayerView for video playback
2. Implement subtitle overlay synchronized with playback
3. Add playback controls (play/pause, speed, seek)

### Phase 3: Subtitle Synchronization
1. Parse transcription timestamps (if available)
2. Display subtitles at correct times during playback
3. Highlight current subtitle segment

## Implementation Steps

### Step 1: Extend File Type Detection

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/Models.swift`

**Add video extensions**:
```swift
// In TranscriptionManager or create separate constant
static let supportedVideoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "flv", "webm", "3gp"]
static let supportedAudioExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]
static let allSupportedExtensions = supportedAudioExtensions + supportedVideoExtensions
```

**Update TranscriptionManager**:
```swift
private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]
private let supportedVideoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "flv", "webm", "3gp"]

func isAudioFile(_ url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    return supportedAudioExtensions.contains(pathExtension)
}

func isVideoFile(_ url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    return supportedVideoExtensions.contains(pathExtension)
}

func isMediaFile(_ url: URL) -> Bool {
    return isAudioFile(url) || isVideoFile(url)
}

// Update findAudioFiles to findVideoFiles or findMediaFiles
func findMediaFiles(in directory: URL) -> [URL] {
    var mediaFiles: [URL] = []

    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return mediaFiles
    }

    for case let fileURL as URL in enumerator {
        if isMediaFile(fileURL) {
            mediaFiles.append(fileURL)
        }
    }

    return mediaFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
}
```

### Step 2: Create Audio Extraction Utility

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/AudioExtractor.swift`

**Create new file**:
```swift
//
//  AudioExtractor.swift
//  WhisperKitTranscriber
//
//  Extracts audio from video files for transcription
//

import Foundation
import AVFoundation

class AudioExtractor {
    static let shared = AudioExtractor()
    private let tempDirectory: URL

    private init() {
        // Create temp directory for extracted audio
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperKitExtractedAudio")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        self.tempDirectory = tempDir
    }

    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        // Load asset tracks
        let tracks = try await asset.loadTracks(withMediaType: .audio)

        guard !tracks.isEmpty else {
            throw AudioExtractionError.noAudioTrack
        }

        // Create output URL
        let outputFileName = "\(UUID().uuidString).m4a"
        let outputURL = tempDirectory.appendingPathComponent(outputFileName)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // Export audio
        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw AudioExtractionError.exportFailed(error.localizedDescription)
            }
            throw AudioExtractionError.exportFailed("Unknown error")
        }

        return outputURL
    }

    func cleanupExtractedAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func cleanupAllExtractedAudio() {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }
}

enum AudioExtractionError: LocalizedError {
    case noAudioTrack
    case exportSessionCreationFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "Video file does not contain an audio track"
        case .exportSessionCreationFailed:
            return "Failed to create audio export session"
        case .exportFailed(let message):
            return "Audio extraction failed: \(message)"
        }
    }
}
```

### Step 3: Update TranscriptionManager for Video Files

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Modify transcribeFile()**:
```swift
private func transcribeFile(_ audioFile: URL, modelPath: String?) async throws -> TranscriptionResult {
    var fileToTranscribe = audioFile
    var extractedAudioURL: URL?
    var isVideoFile = false

    // Check if it's a video file
    if isVideoFile(audioFile) {
        isVideoFile = true
        await MainActor.run {
            statusMessage = "Extracting audio from video: \(audioFile.lastPathComponent)"
        }

        // Extract audio
        do {
            extractedAudioURL = try await AudioExtractor.shared.extractAudio(from: audioFile)
            fileToTranscribe = extractedAudioURL!
        } catch {
            // Cleanup on error
            if let extractedURL = extractedAudioURL {
                AudioExtractor.shared.cleanupExtractedAudio(at: extractedURL)
            }
            throw TranscriptionError.audioExtractionFailed(error.localizedDescription)
        }
    }

    // Proceed with transcription using extracted audio or original file
    do {
        let result = try await transcribeAudioFile(fileToTranscribe, modelPath: modelPath, originalURL: audioFile)

        // Cleanup extracted audio after transcription
        if let extractedURL = extractedAudioURL {
            AudioExtractor.shared.cleanupExtractedAudio(at: extractedURL)
        }

        return result
    } catch {
        // Cleanup extracted audio on error
        if let extractedURL = extractedAudioURL {
            AudioExtractor.shared.cleanupExtractedAudio(at: extractedURL)
        }
        throw error
    }
}

private func transcribeAudioFile(_ audioFile: URL, modelPath: String?, originalURL: URL) async throws -> TranscriptionResult {
    // Existing transcription logic, but use originalURL for result metadata
    // ... existing code ...

    return TranscriptionResult(
        sourcePath: originalURL.path,  // Use original URL, not extracted audio
        fileName: originalURL.lastPathComponent,
        text: transcriptionText,
        duration: duration,
        createdAt: Date(),
        modelUsed: modelUsed
    )
}
```

**Add error case**:
```swift
enum TranscriptionError: LocalizedError {
    // ... existing cases ...
    case audioExtractionFailed(String)

    var errorDescription: String? {
        switch self {
        // ... existing cases ...
        case .audioExtractionFailed(let message):
            return "Failed to extract audio from video: \(message)"
        }
    }
}
```

### Step 4: Create Video Player View

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/VideoPlayerView.swift`

**Create new file**:
```swift
//
//  VideoPlayerView.swift
//  WhisperKitTranscriber
//
//  Video player with subtitle synchronization
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let videoURL: URL
    let transcription: TranscriptionResult?
    @State private var player: AVPlayer?
    @State private var playbackRate: Float = 1.0
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var showSubtitles = true

    // Subtitle segments (will be populated from transcription)
    @State private var subtitleSegments: [SubtitleSegment] = []
    @State private var currentSubtitleIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 400)
                    .onAppear {
                        setupPlayer()
                    }
            } else {
                ProgressView("Loading video...")
                    .frame(height: 400)
            }

            // Controls
            VStack(spacing: 12) {
                // Playback controls
                HStack {
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }

                    // Time display
                    Text(formatTime(currentTime))
                        .font(.monospaced(.caption)())

                    // Seek slider
                    Slider(value: $currentTime, in: 0...duration) { editing in
                        if !editing {
                            seekToTime(currentTime)
                        }
                    }

                    Text(formatTime(duration))
                        .font(.monospaced(.caption)())

                    // Speed control
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { speed in
                            Button("\(String(format: "%.2f", speed))x") {
                                setPlaybackSpeed(speed)
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.2f", playbackRate))x")
                            .font(.caption)
                    }
                }

                // Subtitle toggle
                Toggle("Show Subtitles", isOn: $showSubtitles)
                    .font(.caption)

                // Current subtitle display
                if showSubtitles, let index = currentSubtitleIndex, index < subtitleSegments.count {
                    Text(subtitleSegments[index].text)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        }
        .onAppear {
            loadSubtitles()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var duration: Double {
        guard let player = player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite else {
            return 0
        }
        return duration
    }

    private func setupPlayer() {
        player = AVPlayer(url: videoURL)

        // Observe time updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let observer = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            updateCurrentSubtitle(time: time.seconds)
        }

        // Observe playback status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seekToTime(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }

    private func setPlaybackSpeed(_ speed: Float) {
        playbackRate = speed
        player?.rate = speed
    }

    private func loadSubtitles() {
        guard let transcription = transcription else { return }

        // Convert transcription segments to subtitle segments
        subtitleSegments = transcription.segments.map { segment in
            SubtitleSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text
            )
        }
    }

    private func updateCurrentSubtitle(time: Double) {
        guard showSubtitles else {
            currentSubtitleIndex = nil
            return
        }

        // Find subtitle segment for current time
        if let index = subtitleSegments.firstIndex(where: { time >= $0.startTime && time <= $0.endTime }) {
            currentSubtitleIndex = index
        } else {
            currentSubtitleIndex = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct SubtitleSegment {
    let startTime: Double
    let endTime: Double
    let text: String
}
```

### Step 5: Integrate Video Player into ContentView

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/ContentView.swift`

**Add state**:
```swift
@State private var selectedVideoForPlayback: URL?
@State private var showVideoPlayer = false
```

**Update file row to show play button for videos**:
```swift
// In FileRowView or file list
if transcriptionManager.isVideoFile(fileURL) {
    Button(action: {
        selectedVideoForPlayback = fileURL
        showVideoPlayer = true
    }) {
        Image(systemName: "play.circle.fill")
            .font(.title2)
    }
}
```

**Add video player sheet**:
```swift
.sheet(isPresented: $showVideoPlayer) {
    if let videoURL = selectedVideoForPlayback,
       let transcription = transcriptionManager.completedTranscriptions.first(where: { $0.sourcePath == videoURL.path }) {
        VideoPlayerView(videoURL: videoURL, transcription: transcription)
    }
}
```

### Step 6: Update File Status Display

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/ContentView.swift`

**Add file type indicator**:
```swift
// In file list display
HStack {
    Image(systemName: transcriptionManager.isVideoFile(fileURL) ? "video.fill" : "waveform")
        .foregroundColor(transcriptionManager.isVideoFile(fileURL) ? .blue : .green)
    Text(fileURL.lastPathComponent)
}
```

## Testing Plan

### Unit Tests
1. **Audio Extraction**:
   - Test extraction from various video formats
   - Test video files without audio track
   - Test cleanup of extracted audio
   - Test error handling

2. **File Detection**:
   - Test video file detection
   - Test audio file detection
   - Test unsupported files

### Integration Tests
1. **End-to-End Video Transcription**:
   - Select video file
   - Verify audio extraction
   - Verify transcription
   - Verify cleanup

2. **Video Player**:
   - Test playback controls
   - Test subtitle synchronization
   - Test playback speed changes
   - Test seeking

### Manual Testing Checklist
- [ ] Select video file (MP4, MOV, etc.)
- [ ] Verify audio extraction progress shown
- [ ] Verify transcription completes
- [ ] Open video player
- [ ] Test play/pause
- [ ] Test playback speed changes
- [ ] Test seeking
- [ ] Verify subtitles appear at correct times
- [ ] Test with video without audio track (should show error)
- [ ] Test with various video formats
- [ ] Verify extracted audio is cleaned up

## Edge Cases to Handle

1. **Video without audio**: Show clear error message
2. **Unsupported video format**: Show error, skip file
3. **Extraction failure**: Handle gracefully, show error
4. **Large video files**: Show progress during extraction
5. **Multiple video files**: Process sequentially
6. **No transcription available**: Player works without subtitles
7. **Seeking during playback**: Update subtitle display correctly

## Performance Considerations

1. **Audio extraction**: Can be slow for large videos
   - Show progress indicator
   - Consider background extraction

2. **Memory**: Large video files consume memory
   - Use streaming where possible
   - Clean up extracted audio promptly

3. **Storage**: Extracted audio files use temp space
   - Clean up after transcription
   - Clean up on app quit

## Future Enhancements

1. **Subtitle export**: Export SRT/VTT from video transcription
2. **Video export**: Export video with burned-in subtitles
3. **Multiple audio tracks**: Let user choose which track to transcribe
4. **Video thumbnail**: Show thumbnail in file list
5. **Video metadata**: Display video resolution, codec, etc.
6. **Subtitle styling**: Customize subtitle appearance
7. **Keyboard shortcuts**: Space for play/pause, arrow keys for seek

## Estimated Time

- **Step 1** (File detection): 1 hour
- **Step 2** (Audio extraction): 4-5 hours
- **Step 3** (Transcription integration): 2-3 hours
- **Step 4** (Video player): 6-8 hours
- **Step 5** (UI integration): 2-3 hours
- **Step 6** (File display): 1 hour
- **Testing**: 3-4 hours
- **Total**: ~19-25 hours

## Dependencies

- **AVFoundation**: For audio extraction and video playback (built-in)
- **AVKit**: For VideoPlayer component (built-in)

## Notes

- Audio extraction uses AVAssetExportSession with M4A preset
- Extracted audio is stored in temp directory and cleaned up after use
- Video player requires macOS 11.0+ for VideoPlayer component
- Subtitle synchronization depends on transcription having timestamp data
- Consider adding progress indicator for audio extraction

