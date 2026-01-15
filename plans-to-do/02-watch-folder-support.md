# Implementation Plan: Watch Folder Support

## Overview
Add automatic transcription of audio and video files added to a specified "watch folder". When a new media file is detected in the watched directory, it will be automatically transcribed using the current configuration settings. This enables a "drop and transcribe" workflow where users can simply add files to a folder and have them processed automatically.

**Note**: This feature is designed to work with both audio files and video files (after video support is implemented). For surveillance video use cases, video file support must be implemented first.

**User Feedback Updates**:
- **Recursive Watching**: Must support watching subdirectories (essential for camera structures: `Cam1/Day1/`, `Cam2/Day1/`).
- **Auto-Export**: Transcripts should be saved to an "Exported Transcripts" folder relative to the source file.
- **Pre-Configured Exports**: User must be able to select desired formats (TXT, JSON, SRT, PDF) *before* the automated process begins.

## Current State
- **File selection**: Manual via drag-and-drop or directory browser
- **Transcription trigger**: Manual "Start Transcription" button
- **No automation**: Files must be explicitly selected and processed

## Technical Approach

### Core Technology
Use **FSEventStream** (File System Events API) to monitor directory changes. This is the macOS-native, efficient way to watch for file system changes.

### Architecture
1. **WatchFolderManager**: New class to manage folder watching (recursive)
2. **Settings persistence**: Store watched folder path and **export preferences** in UserDefaults
3. **UI integration**: Add configuration for "Auto-Export Formats" within Watch Folder settings
4. **Automatic processing**: Queue new files, transcribe, and **auto-export** to structure

## Implementation Steps

### Step 1: Create WatchFolderManager Class

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/WatchFolderManager.swift`

**Create new file**:
```swift
//
//  WatchFolderManager.swift
//  WhisperKitTranscriber
//
//  Manages file system watching for automatic transcription
//

import Foundation
import Combine

class WatchFolderManager: ObservableObject {
    @Published var isWatching = false
    @Published var watchedFolderPath: String?
    @Published var processedFiles: Set<String> = []
    @Published var pendingFiles: [URL] = []

    private var eventStream: FSEventStreamRef?
    private var transcriptionCallback: ((URL) -> Void)?
    private let fileManager = FileManager.default
    private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]
    private let supportedVideoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "flv", "webm", "3gp"]

    // Configuration for surveillance video use cases
    @Published var maxConcurrentProcesses: Int = 2  // Limit concurrent transcriptions for large videos
    @Published var fileWriteDelay: TimeInterval = 5.0  // Longer delay for large video files
    @Published var processExistingFilesOnStart: Bool = false  // Don't process existing files (surveillance use case)
    @Published var minFileSizeBytes: Int64 = 0  // Skip very small files (may be incomplete)
    @Published var maxFileAgeSeconds: TimeInterval? = nil  // Only process files newer than X seconds

    // Queue for processing files (to avoid duplicate processing)
    private let processingQueue = DispatchQueue(label: "com.whisperkit.watchfolder", attributes: .concurrent)
    private var processingSet = Set<String>()

    init() {
        // Load saved watch folder from UserDefaults
        if let savedPath = UserDefaults.standard.string(forKey: "watchedFolderPath"),
           fileManager.fileExists(atPath: savedPath) {
            watchedFolderPath = savedPath
        }
    }

    deinit {
        stopWatching()
    }

    func startWatching(folderPath: String, transcriptionCallback: @escaping (URL) -> Void) throws {
        guard fileManager.fileExists(atPath: folderPath) else {
            throw WatchFolderError.folderNotFound
        }

        guard let folderURL = URL(string: "file://\(folderPath)") else {
            throw WatchFolderError.invalidPath
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WatchFolderError.notADirectory
        }

        // Stop existing watch if any
        stopWatching()

        // Store callback
        self.transcriptionCallback = transcriptionCallback

        // Create FSEventStream with Recursive Flag
        let pathsToWatch = [folderPath] as CFArray
        let latency: CFTimeInterval = 1.0  // 1 second latency
        // kFSEventStreamCreateFlagDeep enables recursive watching
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagDeep)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let manager = Unmanaged<WatchFolderManager>.fromOpaque(info).takeUnretainedValue()
                manager.handleFileSystemEvents(
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw WatchFolderError.streamCreationFailed
        }

        eventStream = stream

        // Schedule on run loop
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Start the stream
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            throw WatchFolderError.streamStartFailed
        }

        // Update state
        watchedFolderPath = folderPath
        isWatching = true

        // Save to UserDefaults
        UserDefaults.standard.set(folderPath, forKey: "watchedFolderPath")

        // Process existing files in folder (disabled by default for surveillance use case)
        // Only mark existing files as processed to avoid re-processing
        if processExistingFilesOnStart {
            processExistingFiles(in: folderPath)
        } else {
            markExistingFilesAsProcessed(in: folderPath)
        }
    }

    func stopWatching() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        isWatching = false
    }

    private func handleFileSystemEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

        for (index, path) in paths.enumerated() {
            let flags = eventFlags[index]

            // Check if this is a file creation/modification
            if (flags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0 ||
               (flags & UInt32(kFSEventStreamEventFlagItemModified)) != 0 {

                // Check if it's a media file (audio or video)
                if isMediaFile(path: path) {
                    // Wait longer for large video files to ensure file is fully written
                    // Surveillance systems may write large files over time
                    DispatchQueue.main.asyncAfter(deadline: .now() + fileWriteDelay) { [weak self] in
                        self?.processFile(path: path)
                    }
                }
            }
        }
    }

    private func isAudioFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        return supportedAudioExtensions.contains(ext)
    }

    private func isVideoFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        return supportedVideoExtensions.contains(ext)
    }

    private func isMediaFile(path: String) -> Bool {
        return isAudioFile(path: path) || isVideoFile(path: path)
    }

    private func processFile(path: String) {
        processingQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Check if already processing
            if self.processingSet.contains(path) {
                return
            }

            // Check if file exists and is readable
            guard self.fileManager.fileExists(atPath: path),
                  self.fileManager.isReadableFile(atPath: path) else {
                return
            }

            // Check file size (skip very small files that may be incomplete)
            if let attributes = try? self.fileManager.attributesOfItem(atPath: path),
               let fileSize = attributes[.size] as? Int64,
               fileSize < self.minFileSizeBytes {
                print("⚠️ Skipping file \(path): too small (\(fileSize) bytes)")
                return
            }

            // Check file age (for surveillance: only process recent files)
            if let maxAge = self.maxFileAgeSeconds {
                if let attributes = try? self.fileManager.attributesOfItem(atPath: path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > maxAge {
                        print("⚠️ Skipping file \(path): too old (\(age) seconds)")
                        return
                    }
                }
            }

            // Check if already processed
            if self.processedFiles.contains(path) {
                return
            }

            // Check concurrent processing limit (important for large video files)
            if self.processingSet.count >= self.maxConcurrentProcesses {
                print("⚠️ Processing queue full (\(self.processingSet.count)/\(self.maxConcurrentProcesses)), deferring \(path)")
                // Retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.processFile(path: path)
                }
                return
            }

            // Mark as processing
            self.processingSet.insert(path)

            let fileURL = URL(fileURLWithPath: path)

            // Call transcription callback on main thread
            DispatchQueue.main.async {
                self.transcriptionCallback?(fileURL)

                // Mark as processed after callback completes
                // Note: The callback should handle removing from processingSet when done
            }
        }
    }

    func markFileProcessed(_ path: String) {
        processingQueue.async(flags: .barrier) { [weak self] in
            self?.processingSet.remove(path)
            self?.processedFiles.insert(path)
        }
    }

    func markFileFailed(_ path: String) {
        processingQueue.async(flags: .barrier) { [weak self] in
            self?.processingSet.remove(path)
            // Don't add to processedFiles so it can be retried
        }
    }

    private func processExistingFiles(in folderPath: String) {
        // Process files that already exist in the folder
        // Used when user wants to transcribe existing files
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: folderPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            if isMediaFile(path: fileURL.path) {
                // Queue for processing (respects concurrent limit)
                processFile(path: fileURL.path)
            }
        }
    }

    private func markExistingFilesAsProcessed(in folderPath: String) {
        // Mark existing files as processed without transcribing them
        // Used for surveillance: don't transcribe old files, only new ones
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: folderPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            if isMediaFile(path: fileURL.path) {
                processedFiles.insert(fileURL.path)
            }
        }
    }

    func clearProcessedFiles() {
        processedFiles.removeAll()
    }
}

enum WatchFolderError: LocalizedError {
    case folderNotFound
    case invalidPath
    case notADirectory
    case streamCreationFailed
    case streamStartFailed

    var errorDescription: String? {
        switch self {
        case .folderNotFound:
            return "The specified folder does not exist"
        case .invalidPath:
            return "Invalid folder path"
        case .notADirectory:
            return "The specified path is not a directory"
        case .streamCreationFailed:
            return "Failed to create file system event stream"
        case .streamStartFailed:
            return "Failed to start file system event stream"
        }
    }
}
```

### Step 2: Integrate WatchFolderManager with TranscriptionManager

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Add properties**:
```swift
@Published var watchFolderManager = WatchFolderManager()
@Published var autoTranscribeNewFiles = false
```

**Add method to handle automatic transcription**:
```swift
func setupWatchFolder() {
    guard let folderPath = watchFolderManager.watchedFolderPath else {
        return
    }

    do {
        try watchFolderManager.startWatching(folderPath: folderPath) { [weak self] fileURL in
            guard let self = self else { return }

            // Only auto-transcribe if enabled
            guard self.autoTranscribeNewFiles else {
                // Just add to pending files list
                Task { @MainActor in
                    if !self.audioFiles.contains(fileURL) {
                        self.audioFiles.append(fileURL)
                    }
                }
                return
            }

            // Auto-transcribe the file
            Task {
                await self.transcribeSingleFile(fileURL)
            }
        }
    } catch {
        await MainActor.run {
            showError(message: "Failed to start watching folder: \(error.localizedDescription)")
        }
    }
}

private func transcribeSingleFile(_ fileURL: URL) async {
    // Add file to current batch
    await MainActor.run {
        if !audioFiles.contains(fileURL) {
            audioFiles.append(fileURL)
        }

        // Add to file statuses if not already there
        if !fileStatuses.contains(where: { $0.url == fileURL }) {
            fileStatuses.append(FileStatus(id: UUID(), url: fileURL, status: .pending))
        }
    }

    // Get model path
    let modelPath = getModelPath()

    do {
        // Update status to processing
        await MainActor.run {
            if let index = fileStatuses.firstIndex(where: { $0.url == fileURL }) {
                fileStatuses[index].status = .processing
            }
        }

        // Transcribe (handles both audio and video files)
        let result = try await transcribeFile(fileURL, modelPath: modelPath)

        // Update status and add result
        await MainActor.run {
            if let index = fileStatuses.firstIndex(where: { $0.url == fileURL }) {
                fileStatuses[index].status = .completed
                fileStatuses[index].transcription = result
            }

            if !completedTranscriptions.contains(where: { $0.id == result.id }) {
                completedTranscriptions.append(result)
            }
        }

        // Mark as processed in watch folder manager
        watchFolderManager.markFileProcessed(fileURL.path)
    } catch {
        await MainActor.run {
            if let index = fileStatuses.firstIndex(where: { $0.url == fileURL }) {
                fileStatuses[index].status = .failed(error.localizedDescription)
            }
        }

        // Mark as failed so it can be retried
        watchFolderManager.markFileFailed(fileURL.path)
    }
}
```

### Step 3: Add Watch Folder UI to ContentView

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/ContentView.swift`

**Add state variables**:
```swift
@State private var showWatchFolderPicker = false
@State private var showWatchFolderSettings = false
```

**Add watch folder section** (add after configuration section):
```swift
private var watchFolderSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Watch Folder")
                .font(.headline)
            Spacer()
            if transcriptionManager.watchFolderManager.isWatching {
                Button(action: {
                    transcriptionManager.watchFolderManager.stopWatching()
                }) {
                    Text("Stop Watching")
                        .foregroundColor(.red)
                }
            } else {
                Button(action: {
                    showWatchFolderPicker = true
                }) {
                    Text("Choose Folder")
                }
            }
        }

        if let folderPath = transcriptionManager.watchFolderManager.watchedFolderPath {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                Text(folderPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            Toggle("Auto-transcribe new files", isOn: $transcriptionManager.autoTranscribeNewFiles)
                .help("Automatically transcribe files when they are added to the watch folder")

            if transcriptionManager.autoTranscribeNewFiles {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export Formats:")
                        .font(.caption)
                        .fontWeight(.bold)
                    HStack {
                        Toggle("TXT", isOn: $transcriptionManager.autoExportTxt)
                        Toggle("SRT", isOn: $transcriptionManager.autoExportSrt)
                        Toggle("JSON", isOn: $transcriptionManager.autoExportJson)
                        Toggle("PDF", isOn: $transcriptionManager.autoExportPdf)
                    }
                    .font(.caption)

                    Text("Exports will be saved to: [Source Folder]/Exported Transcripts/")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.leading, 20) // Indent
                .padding(.vertical, 4)
            }

            // Advanced settings for surveillance video use case
            DisclosureGroup("Advanced Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Process existing files on start", isOn: $transcriptionManager.watchFolderManager.processExistingFilesOnStart)
                        .help("If enabled, will transcribe files already in folder when watching starts")

                    HStack {
                        Text("File write delay (seconds):")
                        TextField("", value: $transcriptionManager.watchFolderManager.fileWriteDelay, format: .number)
                            .frame(width: 60)
                    }
                    .help("Wait time before processing new file (longer for large video files)")

                    HStack {
                        Text("Max concurrent processes:")
                        TextField("", value: $transcriptionManager.watchFolderManager.maxConcurrentProcesses, format: .number)
                            .frame(width: 60)
                    }
                    .help("Limit simultaneous transcriptions (important for large video files)")

                    HStack {
                        Text("Min file size (MB):")
                        TextField("", value: Binding(
                            get: { Double(transcriptionManager.watchFolderManager.minFileSizeBytes) / 1_000_000 },
                            set: { transcriptionManager.watchFolderManager.minFileSizeBytes = Int64($0 * 1_000_000) }
                        ), format: .number)
                        .frame(width: 60)
                    }
                    .help("Skip files smaller than this (may be incomplete)")

                    HStack {
                        Text("Max file age (seconds):")
                        TextField("", value: Binding(
                            get: { transcriptionManager.watchFolderManager.maxFileAgeSeconds ?? 0 },
                            set: { transcriptionManager.watchFolderManager.maxFileAgeSeconds = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .frame(width: 100)
                    }
                    .help("Only process files newer than this (0 = no limit)")
                }
                .font(.caption)
            }

            if transcriptionManager.watchFolderManager.isWatching {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Watching for new files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Processed: \(transcriptionManager.watchFolderManager.processedFiles.count) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear History") {
                    transcriptionManager.watchFolderManager.clearProcessedFiles()
                }
                .font(.caption)
            }
        } else {
            Text("No folder selected. Click 'Choose Folder' to start watching.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .padding()
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(8)
    .fileImporter(
        isPresented: $showWatchFolderPicker,
        allowedContentTypes: [.folder],
        allowsMultipleSelection: false
    ) { result in
        switch result {
        case .success(let urls):
            if let url = urls.first {
                let path = url.path
                do {
                    try transcriptionManager.watchFolderManager.startWatching(
                        folderPath: path,
                        transcriptionCallback: { fileURL in
                            if transcriptionManager.autoTranscribeNewFiles {
                                Task {
                                    await transcriptionManager.transcribeSingleFile(fileURL)
                                }
                            } else {
                                Task { @MainActor in
                                    if !transcriptionManager.audioFiles.contains(fileURL) {
                                        transcriptionManager.audioFiles.append(fileURL)
                                    }
                                }
                            }
                        }
                    )
                } catch {
                    transcriptionManager.showError(message: error.localizedDescription)
                }
            }
        case .failure(let error):
            transcriptionManager.showError(message: error.localizedDescription)
        }
    }
}
```

**Add to body** (insert after configuration section):
```swift
// Watch Folder Section
watchFolderSection
    .padding(.horizontal)
```

### Step 4: Initialize Watch Folder on App Launch

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/ContentView.swift`

**Add to `.onAppear` or create init**:
```swift
.onAppear {
    // Restore watch folder if it was set
    if let folderPath = transcriptionManager.watchFolderManager.watchedFolderPath {
        transcriptionManager.setupWatchFolder()
    }
}
```

### Step 5: Handle App Lifecycle

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/WhisperKit_TranscriberApp.swift`

**Add NSApplicationDelegate**:
```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Stop watching on app quit
        // This will be handled by WatchFolderManager deinit, but explicit stop is cleaner
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Resume watching if needed
    }
}
```

**Update app struct**:
```swift
@main
struct WhisperKit_TranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Testing Plan

### Unit Tests
1. **WatchFolderManager**:
   - Test folder path validation
   - Test FSEventStream creation
   - Test file detection
   - Test duplicate prevention
   - Test processed files tracking

2. **File Processing**:
   - Test audio file detection
   - Test non-audio file filtering
   - Test file write completion detection

### Integration Tests
1. **End-to-End**:
   - Create test folder
   - Start watching
   - Add audio file
   - Verify transcription triggered
   - Verify file marked as processed

2. **Edge Cases**:
   - Add file while app is closed (should process on next launch)
   - Add multiple files rapidly
   - Add file, delete it, add again
   - Add file to subdirectory

### Manual Testing Checklist
- [ ] Select watch folder via file picker
- [ ] Verify "Watching" indicator appears
- [ ] Add audio file to watched folder
- [ ] Verify file appears in app (if auto-transcribe disabled)
- [ ] Enable auto-transcribe
- [ ] Add another audio file
- [ ] Verify automatic transcription starts
- [ ] Add video file (after video support implemented)
- [ ] Verify video file detected and processed
- [ ] Test with large video file (surveillance use case)
- [ ] Verify concurrent processing limit respected
- [ ] Test file write delay with large files
- [ ] Test min file size filter
- [ ] Test max file age filter
- [ ] Stop watching folder
- [ ] Verify no new files processed
- [ ] Restart app
- [ ] Verify watch folder restored
- [ ] Test with nested folders
- [ ] Test with non-media files (should be ignored)
- [ ] Test with multiple files added rapidly (surveillance scenario)

## Edge Cases to Handle

1. **File still being written**: Wait configurable delay (default 5 seconds for videos) before processing
2. **Duplicate files**: Track processed files to avoid re-processing
3. **Folder deleted**: Stop watching and show error
4. **Permission denied**: Handle gracefully, show error message
5. **Very large folder**: Don't process all existing files on startup (disabled by default for surveillance)
6. **Network drives**: FSEventStream may not work, handle gracefully
7. **App closed**: Save state, resume on next launch
8. **Multiple files added simultaneously**: Process with configurable concurrent limit (default 2 for large videos)
9. **Large video files**: Handle disk space, processing time, memory usage
10. **Incomplete files**: Skip files smaller than minimum size threshold
11. **Old files**: Optionally skip files older than specified age (for surveillance: only process new recordings)
12. **Processing queue full**: Defer processing and retry later
13. **Video file extraction failures**: Handle audio extraction errors gracefully

## Configuration Options

Add to UserDefaults:
- `watchedFolderPath`: String? - Path to watched folder
- `autoTranscribeNewFiles`: Bool - Auto-transcribe vs just add to list
- `processExistingFilesOnStart`: Bool - Process existing files when starting watch (default: false for surveillance)
- `watchFolderDelay`: Double - Delay before processing new file (default: 5.0 seconds for videos)
- `maxConcurrentProcesses`: Int - Maximum concurrent transcriptions (default: 2 for large videos)
- `minFileSizeBytes`: Int64 - Minimum file size to process (default: 0, no minimum)
- `maxFileAgeSeconds`: TimeInterval? - Maximum file age to process (default: nil, no limit)

## Performance Considerations

1. **FSEventStream latency**: Set to 1.0 second (good balance)
2. **File processing queue**: Use concurrent queue with configurable limit (default 2 for large videos)
3. **Processed files tracking**: Use Set for O(1) lookup
4. **Memory**: Limit processed files set size (e.g., last 1000 files)
5. **Large video files**:
   - Longer write delay (5+ seconds) to ensure file completion
   - Limit concurrent processing to avoid overwhelming system
   - Monitor disk space for extracted audio files
   - Consider cleanup of extracted audio after transcription
6. **Surveillance use case**:
   - Don't process existing files on startup (only new recordings)
   - Process files sequentially or with low concurrency limit
   - Consider file age filtering to only process recent recordings

## Security Considerations

1. **File access**: Only watch folders user explicitly selects
2. **Sandboxing**: May need entitlements for file system access
3. **Permissions**: Request folder access permission if needed

## Future Enhancements

1. **Multiple watch folders**: Support watching multiple directories
2. **File filters**: Filter by file size, date, etc.
3. **Action on completion**: Auto-export, move file, send notification
4. **Filtering**: Advanced regex file filters
5. **Multiple watch folders**: Support multiple root roots
6. **Notification**: Show macOS notification when transcription completes
7. **Surveillance-specific**:
   - Time-based filtering (only process files from certain hours)
   - Camera/channel filtering based on filename patterns
   - Automatic cleanup of old transcriptions
   - Batch export of transcriptions by date/time
   - Motion detection integration (only transcribe when motion detected)

## Estimated Time

- **Step 1** (WatchFolderManager): 4-5 hours
- **Step 2** (Integration): 2-3 hours
- **Step 3** (UI): 2-3 hours
- **Step 4-5** (Lifecycle): 1 hour
- **Testing**: 2-3 hours
- **Total**: ~11-15 hours

## Dependencies

- **Foundation**: FSEventStream API (built-in)
- **Combine**: For @Published properties (already in use)

## Notes

- FSEventStream requires macOS 10.5+ (we target 13.0+, so fine)
- Consider using `DispatchSource.fileSystemObject` as alternative (simpler but less efficient)
- Watch folder state persists across app launches via UserDefaults
- Auto-transcribe can be toggled on/off without stopping watch
- **Video support dependency**: Video file support (plan 04) must be implemented first for surveillance video use case
- **Surveillance optimizations**:
  - Default settings optimized for surveillance: don't process existing files, longer write delay, lower concurrency
  - Large video files require more time and resources - adjust settings accordingly
  - Consider disk space management for extracted audio files
  - May want to implement automatic cleanup of old transcriptions

