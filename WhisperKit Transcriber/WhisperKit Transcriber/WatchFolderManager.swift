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

        // Create FSEventStream
        let pathsToWatch = [folderPath] as CFArray
        let latency: CFTimeInterval = 1.0  // 1 second latency
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

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
