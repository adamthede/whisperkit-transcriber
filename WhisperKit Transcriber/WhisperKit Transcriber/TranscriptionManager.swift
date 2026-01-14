//
//  TranscriptionManager.swift
//  WhisperKitTranscriber
//
//  Manages transcription state and coordinates WhisperKit CLI calls
//

import Foundation
import AVFoundation
import PDFKit
import CoreText
import CoreGraphics
import SwiftUI
import Combine

// Cached regex for token cleaning (Thread-safe, created once)
// Marked @unchecked Sendable to resolve MainActor isolation warnings; NSRegularExpression is thread-safe.
private final class TokenRegexCache: @unchecked Sendable {
    nonisolated(unsafe) static let regex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: "<\\|[^|]+\\|>", options: [])
        } catch {
            print("Error creating regex for cleaning tokens: \(error)")
            return nil
        }
    }()
}

class TranscriptionManager: ObservableObject {
    @Published var audioFiles: [URL] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var batchProgress: Double = 0.0
    @Published var processedFileCount: Int = 0
    @Published var statusMessage = ""
    @Published var selectedModel: WhisperModel = .auto
    @Published var customModelPath: String = "/Users/adam_thede/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB"
    @Published var selectedLanguage: Language = .english
    @Published var completedTranscriptions: [TranscriptionResult] = []
    @Published var fileStatuses: [FileStatus] = []
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false
    @Published var showResults = false


    private let supportedVideoExtensions = ["mp4", "mov"]
    // Removed duplicates: mp4 and mov are video extensions
    private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]

    private var allSupportedExtensions: [String] {
        return supportedAudioExtensions + supportedVideoExtensions
    }

    // Constant for timeout (30 minutes)
    private let transcriptionTimeoutNanoseconds: UInt64 = 1_800_000_000_000



    func reset() {
        audioFiles = []
        completedTranscriptions = []
        fileStatuses = []
        isProcessing = false
        statusMessage = "Idle"
        progress = 0.0
        progress = 0.0
        batchProgress = 0.0
        processedFileCount = 0
        showError = false
        errorMessage = ""
        showSuccess = false
        showResults = false
        currentPreviewText = ""
        currentElapsed = 0
        currentRemaining = 0
    }

    func loadAudioFiles(from directory: URL) {
        audioFiles = findAudioFiles(in: directory)
    }

    func findAudioFiles(in directory: URL) -> [URL] {
        var audioFiles: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return audioFiles
        }

        for case let fileURL as URL in enumerator {
            if isAudioFile(fileURL) {
                audioFiles.append(fileURL)
            }
        }

        return audioFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func isAudioFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        // Allow treating video files as audio sources too (extraction happens later)
        return allSupportedExtensions.contains(pathExtension)
    }

    func isVideoFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return supportedVideoExtensions.contains(pathExtension)
    }

    func startTranscription() async {
        guard !audioFiles.isEmpty else {
            await MainActor.run {
                showError(message: "No audio files selected")
            }
            return
        }

        // Reset state on main actor
        await MainActor.run {
            completedTranscriptions = []
            fileStatuses = audioFiles.map { FileStatus(id: UUID(), url: $0, status: .pending) }
            isProcessing = true
            progress = 0.0
            statusMessage = "Starting transcription..."
            showResults = true
        }

        let totalFiles = Double(audioFiles.count)
        var successfulTranscriptions: [TranscriptionResult] = []
        let modelPathToUse = getModelPath()

        for (index, audioFile) in audioFiles.enumerated() {
            // Update file status to processing on main actor
            await MainActor.run {
                if let statusIndex = fileStatuses.firstIndex(where: { $0.url == audioFile }) {
                    fileStatuses[statusIndex].status = .processing
                }
                // Reset current file progress
                progress = 0.0

                // Update batch progress
                batchProgress = Double(processedFileCount) / totalFiles
                statusMessage = "Processing \(index + 1) of \(audioFiles.count): \(audioFile.lastPathComponent)"
            }

            // Yield to allow UI updates
            await Task.yield()

            do {
                let transcription = try await transcribeFile(audioFile, modelPath: modelPathToUse)
                successfulTranscriptions.append(transcription)

                // Update on main actor
                await MainActor.run {
                    completedTranscriptions.append(transcription)
                    if let statusIndex = fileStatuses.firstIndex(where: { $0.url == audioFile }) {
                        fileStatuses[statusIndex].status = .completed
                        fileStatuses[statusIndex].transcription = transcription
                        fileStatuses[statusIndex].transcription = transcription
                    }
                    processedFileCount += 1
                    batchProgress = Double(processedFileCount) / totalFiles
                }
            } catch {
                let errorMsg = error.localizedDescription
                print("Error transcribing \(audioFile.lastPathComponent): \(errorMsg)")

                // Update file status to failed on main actor
                await MainActor.run {
                    if let statusIndex = fileStatuses.firstIndex(where: { $0.url == audioFile }) {
                        fileStatuses[statusIndex].status = .failed(errorMsg)
                    }
                    // Still increment completed count even on failure so the batch moves forward
                    processedFileCount += 1
                    batchProgress = Double(processedFileCount) / totalFiles
                }
            }

            // Yield periodically to keep UI responsive
            await Task.yield()
        }

        await MainActor.run {
            if successfulTranscriptions.isEmpty {
                showError(message: "No files were successfully transcribed. Please check the errors above.")
            }
            self.isProcessing = false
            self.statusMessage = "Transcription complete: \(successfulTranscriptions.count) of \(audioFiles.count) files"
            self.progress = 1.0
        }
    }

    @Published var currentPreviewText: String = ""
    @Published var currentElapsed: TimeInterval = 0
    @Published var currentRemaining: TimeInterval = 0

    func parseProgress(from line: String) {

        // Expected format: "[===] 33% | Elapsed Time: 22.86 s | Remaining: 45.42 s"

        let parts = line.components(separatedBy: "|")
        var elapsed: Double = 0
        var remaining: Double = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Elapsed Time:") {
                let cleanVal = trimmed
                    .replacingOccurrences(of: "Elapsed Time:", with: "")
                    .replacingOccurrences(of: "s", with: "") // Remove 's' suffix
                    .trimmingCharacters(in: .whitespaces)
                elapsed = parseDuration(cleanVal)
            } else if trimmed.contains("Remaining:") {
                let cleanVal = trimmed
                    .replacingOccurrences(of: "Remaining:", with: "")
                    .replacingOccurrences(of: "s", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Handle "Estimating..." case
                if cleanVal.lowercased().contains("estimating") {
                    remaining = 0
                } else {
                    remaining = parseDuration(cleanVal)
                }
            }
        }

        if elapsed > 0 {
             self.currentElapsed = elapsed
             self.currentRemaining = remaining

             let total = elapsed + remaining
             if total > 0 {
                 self.progress = elapsed / total
             }
        }
    }

    func parseLiveText(from line: String) {
        // Expected format: "[00:00:00.000 --> 00:00:04.000]  Some transcribed text"
        guard let bracketEnd = line.firstIndex(of: "]") else {
            return
        }
        let textPart = line[line.index(after: bracketEnd)...].trimmingCharacters(in: .whitespaces)
        if !textPart.isEmpty {
            if self.currentPreviewText.isEmpty {
                self.currentPreviewText = textPart
            } else {
                 self.currentPreviewText += " " + textPart
            }
        }
    }

    // Moved to be an instance method or ensure correct scope
    private func parseDuration(_ durationString: String) -> Double {
        // Handle "00:00:00" format
        if durationString.contains(":") {
            let parts = durationString.components(separatedBy: ":")
            guard parts.count == 3,
                  let h = Double(parts[0]),
                  let m = Double(parts[1]),
                  let s = Double(parts[2]) else { return 0 }
            return h * 3600 + m * 60 + s
        } else {
            // Handle raw seconds "22.86"
            return Double(durationString) ?? 0
        }
    }

    func getModelPath() -> String? {
        switch selectedModel {
        case .auto:
            return nil
        case .custom:
            return customModelPath.isEmpty ? nil : customModelPath
        default:
            // For named models, WhisperKit CLI handles them automatically
            // But we can pass model name if CLI supports it
            return nil
        }
    }

    private func updateProgressFromLine(_ line: String, fileName: String) async {
        // Parse common progress messages from whisperkit-cli
        let lowercased = line.lowercased()

        await MainActor.run {
            if lowercased.contains("loading") || lowercased.contains("model") {
                statusMessage = "Loading model for \(fileName)..."
            } else if lowercased.contains("processing") || lowercased.contains("audio") {
                statusMessage = "Processing audio: \(fileName)..."
            } else if lowercased.contains("transcribing") {
                statusMessage = "Transcribing: \(fileName)..."
            } else if lowercased.contains("transcription of") {
                statusMessage = "Extracting text from \(fileName)..."
            } else if lowercased.contains("error") || lowercased.contains("failed") {
                statusMessage = "Error processing \(fileName)"
            } else if lowercased.contains("complete") || lowercased.contains("done") {
                statusMessage = "Completed: \(fileName)"
            } else {
                // Update with generic status if we see activity
                statusMessage = "Processing \(fileName)..."
            }
        }

        // Also print to console for debugging
        print("📊 [\(fileName)] \(line)")
    }

    private func transcribeFile(_ audioFile: URL, modelPath: String?) async throws -> TranscriptionResult {
        // Check if whisperkit-cli is available
        guard let whisperkitPath = findWhisperKitCLI() else {
            let errorMsg = """
            WhisperKit CLI not found. Please ensure whisperkit-cli is installed.

            Install with: pip install whisperkit

            Or ensure it's in one of these locations:
            - /opt/homebrew/bin/whisperkit-cli (Apple Silicon)
            - /usr/local/bin/whisperkit-cli (Intel)
            - In your PATH

            Check Console for detailed search results.
            """
            print("❌ \(errorMsg)")
            throw TranscriptionError.whisperKitNotFound
        }

        // Check if we need to extract audio first
        var processAudioFile = audioFile
        var extractedAudioURL: URL?

        if isVideoFile(audioFile) {
            await MainActor.run {
                statusMessage = "Extracting audio from video..."
            }
            do {
                let extractedURL = try await AudioExtractor.shared.extractAudio(from: audioFile)
                extractedAudioURL = extractedURL
                processAudioFile = extractedURL
                print("✅ Audio extracted to: \(processAudioFile.path)")
            } catch {
                print("❌ Audio extraction failed: \(error.localizedDescription)")
                throw error
            }
        }

        defer {
             if let extractedURL = extractedAudioURL {
                 AudioExtractor.shared.cleanup(url: extractedURL)
             }
         }

        print("🎤 Transcribing: \(audioFile.lastPathComponent)")
        print("   Using: \(whisperkitPath)")

        let uniqueReportDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: uniqueReportDir, withIntermediateDirectories: true, attributes: nil)

        // Build command
        var arguments: [String] = [
            "transcribe",
            "--audio-path", processAudioFile.path,
            "--language", selectedLanguage.code,
            "--verbose",
            "--report",
            "--report-path", uniqueReportDir.path
        ]

        // Add model selection
        if let modelPath = modelPath, !modelPath.isEmpty {
            arguments.append("--model-path")
            arguments.append(modelPath)
            print("   Model: \(modelPath)")
        } else if selectedModel != .auto && selectedModel != .custom {
            // Try to use model name directly (if CLI supports it)
            arguments.append("--model")
            arguments.append(selectedModel.rawValue)
            print("   Model: \(selectedModel.rawValue)")
        } else {
            print("   Model: auto-select")
        }

        print("   Command: whisperkit-cli \(arguments.joined(separator: " "))")

        // Run whisperkit-cli through shell using command name
        // This lets the shell's PATH resolve it, avoiding sandboxing issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Use login shell (-l) to get full PATH with Homebrew
        // Properly quote arguments to handle spaces, parentheses, and special chars
        let quotedArgs = arguments.map { arg -> String in
            // Single-quote the argument and escape any single quotes inside
            let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        let commandString = "whisperkit-cli \(quotedArgs.joined(separator: " "))"
        process.arguments = ["-l", "-c", commandString]

        // Set environment to ensure PATH includes Homebrew
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Configure pipe to avoid blocking
        pipe.fileHandleForReading.readabilityHandler = nil

        // Collect output incrementally using actor for thread safety
        actor OutputCollector {
            private var lines: [String] = []
            private var buffer: String = ""
            weak var manager: TranscriptionManager?
            var fileName: String = ""

            init(manager: TranscriptionManager? = nil, fileName: String = "") {
                self.manager = manager
                self.fileName = fileName
            }

            func append(_ text: String) {
                buffer += text
                let allLines = buffer.components(separatedBy: .newlines)
                buffer = allLines.last ?? ""

                for line in allLines.dropLast() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // DEBUG: Optionally print raw CLI lines to Xcode console.
                        // Enable by setting environment variable WHISPERKIT_DEBUG_CLI=1 in the scheme.
                        #if DEBUG
                        if ProcessInfo.processInfo.environment["WHISPERKIT_DEBUG_CLI"] == "1" {
                            print("🤖 [CLI Raw]: \(trimmed)")
                        }
                        #endif

                        // Parse progress from "Elapsed Time" lines
                        // Example: "Elapsed Time: 00:00:05, Remaining: 00:00:20"
                        if trimmed.contains("Elapsed Time:") && trimmed.contains("Remaining:") {
                            // Weak self capture is correct; manager is weak in init but we capture it again weakly here
                            // just to be safe and explicit about the closure context
                            Task { @MainActor [weak manager] in
                                manager?.parseProgress(from: trimmed)
                            }
                            continue
                        }

                        // Parse timestamps for live preview
                        // Example: "[00:00:00.000 --> 00:00:05.000]  Hello world"
                        if trimmed.contains("-->") && trimmed.contains("[") && trimmed.contains("]") {
                            Task { @MainActor [weak manager] in
                                manager?.parseLiveText(from: trimmed)
                            }
                        }

                        // Also filter out raw control sequences that might appear
                        if trimmed.contains("[K") && trimmed.contains("=") {
                            continue
                        }

                        lines.append(trimmed)
                    }
                }
            }

            func getLines() -> [String] {
                return lines
            }

            func getBuffer() -> String {
                return buffer
            }

            func addRemaining(_ text: String) {
                buffer += text
                let allLines = buffer.components(separatedBy: .newlines)
                for line in allLines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        lines.append(trimmed)
                    }
                }
                buffer = ""
            }
        }

        let collector = OutputCollector(manager: self, fileName: audioFile.lastPathComponent)
        let errorCollector = OutputCollector()

        // Create pipe for standard error as well
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Read output in real-time with proper handling
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return } // EOF

            if let text = String(data: data, encoding: .utf8) {
                Task {
                    await collector.append(text)
                    let lines = await collector.getLines()
                    if let lastLine = lines.last {
                        // Update UI with progress messages
                        Task { @MainActor in
                            await self.updateProgressFromLine(lastLine, fileName: audioFile.lastPathComponent)
                        }
                    }
                }
            }
        }

        // Read stderr in real-time
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return } // EOF

            if let text = String(data: data, encoding: .utf8) {
                Task {
                    await errorCollector.append(text)
                }
            }
        }

        var output: String
        do {
            try process.run()

            // Update status to show we're processing (on main actor)
            await MainActor.run {
                statusMessage = "Processing \(audioFile.lastPathComponent)..."
            }

            // Wait for process to complete with timeout


            // Wait for process to complete with timeout
            // CRITICAL FIX: Use Task.detached to run blocking waitUntilExit() on a background thread.
            // A normal Task would inherit the MainActor context from the caller, freezing the UI.
            let exitTask = Task.detached(priority: .userInitiated) {
                process.waitUntilExit()
                return false // did not timeout
            }

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: transcriptionTimeoutNanoseconds)
                return true // did timeout
            }

            var didTimeout = false

            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await exitTask.value
                }
                group.addTask {
                    do {
                        return try await timeoutTask.value
                    } catch {
                        return false
                    }
                }

                if let firstResult = await group.next() {
                    didTimeout = firstResult
                    // Cancel the other task
                    if didTimeout {
                        exitTask.cancel()
                        // Note: cancelling exitTask doesn't stop waitUntilExit, but process.terminate() below will.
                    } else {
                        timeoutTask.cancel()
                    }
                }
            }

            // Allow any pending cancellations to propagate
            if didTimeout {
                print("⚠️ Process timeout after 30 minutes, terminating...")
                await MainActor.run {
                    statusMessage = "Timeout: Terminating process..."
                }
                process.terminate()
                // Give it 5 seconds to terminate gracefully, yielding periodically
                for _ in 0..<50 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms chunks
                    await Task.yield() // Yield to UI
                }

                throw TranscriptionError.transcriptionFailed("Transcription timed out after 30 minutes")
            }

            // Wait a bit for final output, yielding periodically
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms chunks
                await Task.yield() // Yield to UI
            }

            // Stop reading
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            // Get any remaining output
            // Get any remaining output and flush to collector
            let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remainingData, encoding: .utf8), !text.isEmpty {
                await collector.addRemaining(text)
            }

            let remainingErrorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: remainingErrorData, encoding: .utf8) {
                await errorCollector.append(text)
            }

            // output will be constructed from lines mostly
            let errorOutput = await errorCollector.getBuffer()

            print("📊 Process finished with exit code: \(process.terminationStatus)")
            if !errorOutput.isEmpty {
                print("⚠️ Process Stderr Output:\n\(errorOutput)")
            }

            output = await collector.getLines().joined(separator: "\n")

            // Check if we got transcription text even if process was terminated
            // Exit code 15 (SIGTERM) often means cancellation but transcription may have completed
            let hasTranscription = output.contains("Transcription of") || output.contains("Transcription:")

            // If we have transcription text, try to extract it even if exit code is non-zero
            if hasTranscription && process.terminationStatus != 0 {
                print("⚠️ Process exited with code \(process.terminationStatus) but transcription may be complete")
                print("   Attempting to extract transcription from output...")
                // Continue to extraction below - don't throw error yet
            } else if process.terminationStatus != 0 {
                print("❌ Transcription failed for \(audioFile.lastPathComponent)")
                print("   Exit code: \(process.terminationStatus)")
                print("   Output preview: \(output.prefix(500))")
                await MainActor.run {
                    statusMessage = "Failed: \(audioFile.lastPathComponent)"
                }
                throw TranscriptionError.transcriptionFailed(output.isEmpty ? "Unknown error (exit code: \(process.terminationStatus))" : output)
            }

            print("✅ Transcription completed for \(audioFile.lastPathComponent)")
            await MainActor.run {
                statusMessage = "Completed: \(audioFile.lastPathComponent)"
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            print("❌ Error running whisperkit-cli: \(error)")
            await MainActor.run {
                statusMessage = "Error: \(audioFile.lastPathComponent)"
            }
            if let urlError = error as? CocoaError, urlError.code == .fileReadNoSuchFile {
                throw TranscriptionError.whisperKitNotFound
            }
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }

        // Parse JSON report to get segments (in a detached task to avoid blocking main thread)
        let parsingTask = Task.detached(priority: .userInitiated) { () -> ([TranscriptionSegment], String) in
            var segments: [TranscriptionSegment] = []
            var transcriptionText = ""
            var reportFile: URL? = nil

            // Find the json file in the unique directory
            do {
                let files = try FileManager.default.contentsOfDirectory(at: uniqueReportDir, includingPropertiesForKeys: nil)
                reportFile = files.first(where: { $0.pathExtension == "json" })
            } catch {
                print("⚠️ Failed to list contents of report directory: \(error)")
            }

            if let reportURL = reportFile {
                 do {
                     let data = try Data(contentsOf: reportURL)
                     if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                         // Try standard "segments" key first (WhisperKit default)
                         if let segmentsJson = json["segments"] as? [[String: Any]] {
                             var idCounter = 0
                             for result in segmentsJson {
                                 if let text = result["text"] as? String,
                                    let start = result["start"] as? Double,
                                    let end = result["end"] as? Double {
                                     let cleanedText = TranscriptionManager.cleanWhisperTokens(from: text)
                                     let segment = TranscriptionSegment(
                                         id: idCounter,
                                         start: start,
                                         end: end,
                                         text: cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                     )
                                     segments.append(segment)
                                     transcriptionText += segment.text + " " // Use space for continuity
                                     idCounter += 1
                                 }
                             }
                             // Clean up double spaces if any
                             transcriptionText = transcriptionText.replacingOccurrences(of: "  ", with: " ")

                         } else if let results = json["results"] as? [[String: Any]] {
                             // Fallback to "results" key
                             var idCounter = 0
                             for result in results {
                                 if let text = result["text"] as? String,
                                    let start = result["start"] as? Double,
                                    let end = result["end"] as? Double {
                                     let cleanedText = TranscriptionManager.cleanWhisperTokens(from: text)
                                     let segment = TranscriptionSegment(
                                         id: idCounter,
                                         start: start,
                                         end: end,
                                         text: cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                     )
                                     segments.append(segment)
                                     transcriptionText += segment.text + " "
                                     idCounter += 1
                                 }
                             }
                         } else {
                             // If no segments found, maybe there is a top-level text?
                             if let fullText = json["text"] as? String {
                                  transcriptionText = TranscriptionManager.cleanWhisperTokens(from: fullText)
                             }
                         }
                     }
                 } catch {
                     print("⚠️ Failed to parse report.json: \(error)")
                 }
            }
            return (segments, transcriptionText)
        }

        let parsingResult = await parsingTask.value

        let segments = parsingResult.0
        var transcriptionText = parsingResult.1



        // Fallback to text parsing from output if JSON fails or returned empty text
        if transcriptionText.isEmpty {
            transcriptionText = extractTextFromOutput(output)
        }

        // Clean any remaining artifacts if parsing failed
        // (Note: The JSON parsing above already cleans individual segments)
        if segments.isEmpty {
            transcriptionText = TranscriptionManager.cleanWhisperTokens(from: transcriptionText)
        }

        // Clean up report directory
        try? FileManager.default.removeItem(at: uniqueReportDir)

        transcriptionText = transcriptionText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if transcriptionText.isEmpty {
            // If process was terminated but we have output, it might be in a different format
            if process.terminationStatus != 0 && !output.isEmpty {
                print("⚠️ Warning: Process exited with code \(process.terminationStatus) and no transcription found")
                print("   This may indicate the process was cancelled before completion")
                print("   Output preview: \(output.prefix(500))")
                throw TranscriptionError.transcriptionFailed("Transcription was cancelled or interrupted (exit code: \(process.terminationStatus))")
            } else {
                print("⚠️ Warning: No transcription text extracted from output")
                print("   Output preview: \(output.prefix(500))")
                throw TranscriptionError.transcriptionFailed("No transcription text found in output")
            }
        }

        // Get file duration if possible
        let duration = getAudioDuration(audioFile)

        let modelUsed = modelPath ?? (selectedModel == .auto ? "auto" : selectedModel.rawValue)

        return TranscriptionResult(
            sourcePath: audioFile.path,
            fileName: audioFile.lastPathComponent,
            text: transcriptionText,
            segments: segments,
            duration: duration,
            createdAt: Date(),
            modelUsed: modelUsed
        )
    }

    private func extractTextFromOutput(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var text = ""
        var foundTranscription = false

        for line in lines {
            if foundTranscription {
                text += line + "\n"
            } else if line.hasPrefix("Transcription of") {
                foundTranscription = true
            }
        }
        return text
    }

    nonisolated private static func cleanWhisperTokens(from text: String) -> String {
        // Use cached regex
        guard let regex = TokenRegexCache.regex else { return text }

        let range = NSRange(location: 0, length: text.utf16.count)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findWhisperKitCLI() -> String? {
        // Check common locations (order matters - check most common first)
        let possiblePaths = [
            "/opt/homebrew/bin/whisperkit-cli",  // Apple Silicon Homebrew
            "/usr/local/bin/whisperkit-cli",      // Intel Homebrew
            "/usr/bin/whisperkit-cli",            // System location
            "\(NSHomeDirectory())/.local/bin/whisperkit-cli",  // User local bin
            "\(NSHomeDirectory())/bin/whisperkit-cli"          // User bin
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                // Use the symlink path directly - shell will resolve it
                // This avoids sandboxing issues with resolved paths
                print("✅ Found whisperkit-cli at: \(path)")
                return path
            }
        }

        // Try to find it using shell PATH (more reliable)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-l", "-c", "which whisperkit-cli"]

        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = pipe

        do {
            try shell.run()
            shell.waitUntilExit()

            if shell.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.fileExists(atPath: path) {
                    // Use the path from PATH directly - shell will resolve symlinks
                    print("✅ Found whisperkit-cli via PATH: \(path)")
                    return path
                }
            }
        } catch {
            print("⚠️ Error running 'which whisperkit-cli': \(error)")
        }

        // Log all checked paths for debugging
        print("❌ whisperkit-cli not found. Checked paths:")
        for path in possiblePaths {
            let exists = FileManager.default.fileExists(atPath: path)
            print("   \(exists ? "✅" : "❌") \(path)")
        }

        return nil
    }

    private func getAudioDuration(_ audioFile: URL) -> Int? {
        // Try to use ffprobe if available
        guard let ffprobePath = findFFProbe() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            audioFile.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let duration = Double(output) {
                    return Int(duration)
                }
            }
        } catch {
            // Ignore
        }

        return nil
    }

    private func findFFProbe() -> String? {
        let possiblePaths = [
            "/usr/local/bin/ffprobe",
            "/opt/homebrew/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    func exportTranscriptions(format: ExportFormat, outputPath: String, includeTimestamp: Bool = true, alsoExportIndividual: Bool = false) throws {
        let transcriptions = completedTranscriptions

        // Add timestamp to filename if requested
        let finalOutputPath = includeTimestamp && format != .individualFiles ? addTimestampToFilename(outputPath, format: format) : outputPath

        switch format {
        case .markdown:
            try exportMarkdown(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamp: includeTimestamp)
        case .plainText:
            try exportPlainText(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamp: includeTimestamp)
        case .json:
            try exportJSON(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .srt:
            try exportSRT(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .vtt:
            try exportVTT(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .html:
            try exportHTML(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .pdf:
            try exportPDF(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .individualFiles:
            try exportIndividualFiles(transcriptions: transcriptions, outputDir: outputPath, includeTimestamp: includeTimestamp)
        }

        // If also exporting individual files, do that too
        if alsoExportIndividual && format != .individualFiles {
            let individualDir = URL(fileURLWithPath: finalOutputPath).deletingLastPathComponent().path
            try exportIndividualFiles(transcriptions: transcriptions, outputDir: individualDir, includeTimestamp: includeTimestamp)
        }
    }

    private func addTimestampToFilename(_ path: String, format: ExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent().path
        let filename = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? format.fileExtension : url.pathExtension

        return "\(directory)/\(timestamp)_\(filename).\(fileExtension)"
    }

    private func exportMarkdown(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamp: Bool) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var markdown = ""

        // YAML front matter
        markdown += "---\n"
        markdown += "combined_from: \(transcriptions.count) files\n"
        markdown += "created_utc: \"\(formatter.string(from: Date()))\"\n"
        markdown += "format: combined_markdown\n"
        markdown += "---\n\n"

        markdown += "# Combined Audio Transcription\n\n"

        // Add each transcription
        for transcription in transcriptions {
            let fileName = (transcription.fileName as NSString).deletingPathExtension
            markdown += "## \(fileName)\n\n"

            // Add metadata if available
            if let duration = transcription.duration {
                markdown += "*Duration: \(TranscriptionManager.formatDuration(TimeInterval(duration)))*\n\n"
            }

            if includeTimestamp, !transcription.segments.isEmpty {
                 markdown += formatToTimestampedText(transcription.segments)
            } else {
                 markdown += "\(transcription.displayText)\n\n"
            }

            markdown += "\n*Source: \(transcription.fileName)*\n"
            markdown += "---\n\n"
        }

        // Write to file
        try markdown.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportPlainText(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamp: Bool) throws {
        var text = "Combined Audio Transcription\n"
        text += "\(String(repeating: "=", count: 30))\n\n"

        for transcription in transcriptions {
            text += "\(transcription.fileName)\n"
            text += "\(String(repeating: "-", count: transcription.fileName.count))\n\n"
            if let duration = transcription.duration {
                text += "Duration: \(TranscriptionManager.formatDuration(TimeInterval(duration)))\n\n"
            }

            if includeTimestamp, !transcription.segments.isEmpty {
                text += formatToTimestampedText(transcription.segments)
            } else {
                text += "\(transcription.displayText)\n\n"
            }

            text += "\nSource: \(transcription.fileName)\n"
            text += "\(String(repeating: "-", count: 50))\n\n"
        }

        try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportJSON(transcriptions: [TranscriptionResult], outputPath: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let jsonObject: [String: Any] = [
            "metadata": [
                "combined_from": transcriptions.count,
                "created_utc": formatter.string(from: Date()),
                "format": "json"
            ],
            "transcriptions": transcriptions.map { transcription in
                [
                    "source_path": transcription.sourcePath,
                    "file_name": transcription.fileName,
                    "text": transcription.displayText,
                    "duration_seconds": transcription.duration as Any,
                    "created_at": formatter.string(from: transcription.createdAt),
                    "model_used": transcription.modelUsed as Any
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
        try jsonData.write(to: URL(fileURLWithPath: outputPath))
    }

    func exportIndividualFiles(transcriptions: [TranscriptionResult], outputDir: String, includeTimestamp: Bool = false, format: ExportFormat = .markdown) throws {
        let outputURL = URL(fileURLWithPath: outputDir)
        // Only create directory if it doesn't exist (it holds the outputs)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let batchTimestamp = timestampFormatter.string(from: Date())

        for transcription in transcriptions {
            let baseFileName = (transcription.fileName as NSString).deletingPathExtension
            let ext = format == .individualFiles ? "md" : format.fileExtension // .individualFiles is an export mode that defaults to markdown, so we force "md" as the extension here

            let fileName: String
            if includeTimestamp {
                fileName = "\(batchTimestamp)_\(baseFileName).\(ext)"
            } else {
                fileName = "\(baseFileName).\(ext)"
            }
            let fileURL = outputURL.appendingPathComponent(fileName)
            let individualOutputPath = fileURL.path

            // Use the specific export function for a single item
            switch format {
            case .markdown, .individualFiles:
                try exportMarkdown(transcriptions: [transcription], outputPath: individualOutputPath, includeTimestamp: includeTimestamp)
            case .plainText:
                try exportPlainText(transcriptions: [transcription], outputPath: individualOutputPath, includeTimestamp: includeTimestamp)
            case .json:
                try exportJSON(transcriptions: [transcription], outputPath: individualOutputPath)
            case .srt:
                try exportSRT(transcriptions: [transcription], outputPath: individualOutputPath)
            case .vtt:
                try exportVTT(transcriptions: [transcription], outputPath: individualOutputPath)
            case .html:
                try exportHTML(transcriptions: [transcription], outputPath: individualOutputPath)
            case .pdf:
                try exportPDF(transcriptions: [transcription], outputPath: individualOutputPath)
            }
        }
    }

    private func exportSRT(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var srtContent = ""

        for (index, transcription) in transcriptions.enumerated() {
            // For combined SRT exports, append each file's subtitles sequentially.

            if index > 0 {
                srtContent += "\n\n"
            }

            srtContent += formatToSRT(transcription.segments)

            // Add a final subtitle segment indicating the source file name.
            let lastEnd = transcription.segments.last?.end ?? 0
            let sourceStart = createSRTTimestamp(lastEnd + 1)
            let sourceEnd = createSRTTimestamp(lastEnd + 5)
            let sourceSubtitleIndex = transcription.segments.count + 1
            srtContent += "\n\(sourceSubtitleIndex)\n\(sourceStart) --> \(sourceEnd)\nSource: \(transcription.fileName)\n"
        }

        try srtContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func formatToSRT(_ segments: [TranscriptionSegment]) -> String {
        var output = ""
        for (index, segment) in segments.enumerated() {
            let sequenceNumber = index + 1
            let startTime = createSRTTimestamp(segment.start)
            let endTime = createSRTTimestamp(segment.end)

            // Handle multiline text in segment if any locally
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

            output += "\(sequenceNumber)\n"
            output += "\(startTime) --> \(endTime)\n"
            output += "\(text)\n\n"
        }
        return output
    }

    private func createSRTTimestamp(_ seconds: Double) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hrs, mins, secs, millis)
    }

    private func formatToTimestampedText(_ segments: [TranscriptionSegment]) -> String {
        var output = ""
        for segment in segments {
            let timestamp = String(format: "[%02d:%02d:%02d]",
                                   Int(segment.start) / 3600,
                                   (Int(segment.start) % 3600) / 60,
                                   Int(segment.start) % 60)
            output += "\(timestamp) \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        return output + "\n"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "00:00"
    }

    func updateTranscription(_ transcription: TranscriptionResult, editedText: String) {
        if let transcription = completedTranscriptions.first(where: { $0.id == transcription.id }) {
            transcription.editedText = editedText
        }
    }

    func showError(message: String) {
        errorMessage = message
        showError = true
    }



    // MARK: - Advanced Exports (VTT, HTML, PDF)

    private func exportVTT(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var vtt = "WEBVTT\n\n"

        for transcription in transcriptions {
            // Add file header note
            vtt += "NOTE Transcription of \(transcription.fileName)\n\n"

            if transcription.segments.isEmpty {
                // If no segments, just dump the text as a single block 00:00 -> duration
                let duration = transcription.duration ?? 0
                vtt += "00:00.000 --> \(formatTimestampVTT(Double(duration)))\n"
                vtt += "\(transcription.displayText)\n\n"
            } else {
                for segment in transcription.segments {
                    vtt += "\(formatTimestampVTT(segment.start)) --> \(formatTimestampVTT(segment.end))\n"
                    vtt += "\(segment.text)\n\n"
                }
            }
            vtt += "NOTE Source: \(transcription.fileName)\n\n"
        }

        try vtt.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportHTML(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Transcription Export</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; color: #333; }
                .transcription { margin-bottom: 40px; border-bottom: 1px solid #eee; padding-bottom: 20px; }
                h1 { color: #007AFF; }
                h2 { border-bottom: 2px solid #f0f0f0; padding-bottom: 10px; margin-top: 30px; }
                .meta { color: #666; font-size: 0.9em; margin-bottom: 15px; }
                .segment { margin-bottom: 10px; }
                .timestamp { color: #888; font-family: monospace; font-size: 0.85em; margin-right: 10px; background: #f5f5f5; padding: 2px 6px; border-radius: 4px; }
                .text { }
            </style>
        </head>
        <body>
            <h1>Transcription Export</h1>
            <p class="meta">Generated by WhisperKit Transcriber on \(Date().formatted())</p>

        """

        for transcription in transcriptions {
            html += """
            <div class="transcription">
                <h2>\(transcription.fileName)</h2>
                \(transcription.duration != nil ? "<p class='meta'>Duration: \(TranscriptionManager.formatDuration(TimeInterval(transcription.duration!)))</p>" : "")
            """

            if !transcription.segments.isEmpty {
                for segment in transcription.segments {
                    html += """
                    <div class="segment">
                        <span class="timestamp">\(formatTimestamp(segment.start))</span>
                        <span class="text">\(segment.text)</span>
                    </div>
                    """
                }
            } else {
                // Pre-formatted text for fallback
                html += "<pre class='text'>\(transcription.displayText)</pre>"
            }

            html += "<p class='meta'>Source: \(transcription.fileName)</p>"
            html += "</div>"
        }

        html += """
        </body>
        </html>
        """

        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportPDF(transcriptions: [TranscriptionResult], outputPath: String) throws {
        // PDF Export Implementation
        // Note: For a robust implementation, PDFKit can be used.
        // For simplicity in this iteration, we will rely on a basic PDF drawing approach.

        // Setup PDF Data
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData)!
        var rect = CGRect(x: 0, y: 0, width: 612, height: 792) // Standard Letter size

        guard let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else {
            throw TranscriptionError.exportFailed("Could not create PDF context")
        }

        // PDF Generation Logic
        // We need to use CoreText or simple string drawing.
        // Since we are in a swift file without NSView/UIView context easily, using CoreGraphics/CoreText is best.

        // Standard margins
        let margin: CGFloat = 50
        var cursorY: CGFloat = 792 - margin

        func checkPageBreak(heightNeeded: CGFloat) {
            if cursorY - heightNeeded < margin {
                context.endPage()
                context.beginPage(mediaBox: &rect)
                cursorY = 792 - margin
            }
        }

        // Begin First Page
        context.beginPage(mediaBox: &rect)

        // Title Attributes
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let monoFont = CTFontCreateWithName("Courier" as CFString, 10, nil)

        // Draw Main Title
        drawText("Transcription Export", font: titleFont, x: margin, y: &cursorY, context: context)
        cursorY -= 20
        drawText("Generated: \(Date().formatted())", font: bodyFont, x: margin, y: &cursorY, context: context)
        cursorY -= 40

        for transcription in transcriptions {
            checkPageBreak(heightNeeded: 100)

            // File Title
            drawText("File: \(transcription.fileName)", font: titleFont, x: margin, y: &cursorY, context: context)
            cursorY -= 20

            if let duration = transcription.duration {
                drawText("Duration: \(TranscriptionManager.formatDuration(TimeInterval(duration)))", font: bodyFont, x: margin, y: &cursorY, context: context)
                cursorY -= 20
            }

            cursorY -= 10

            if !transcription.segments.isEmpty {
                for segment in transcription.segments {
                    checkPageBreak(heightNeeded: 20)

                    let timeString = "[\(formatTimestamp(segment.start))]"
                    drawText(timeString, font: monoFont, x: margin, y: &cursorY, context: context)

                    // Simple text wrapping is complex with CoreText manual drawing.
                    // For MPV (Minimum Viable Product), we will just draw the text line.
                    // TODO: Implement full multi-line wrapping for PDF to avoid truncation of long lines.
                    drawText(segment.text, font: bodyFont, x: margin + 80, y: &cursorY, context: context, alignOnSameLine: true)

                    cursorY -= 15
                }
            } else {
                // Draw full text (basic wrapping not implemented for block text in this simple version)
                drawText(transcription.displayText, font: bodyFont, x: margin, y: &cursorY, context: context)
            }

            cursorY -= 15
            drawText("Source: \(transcription.fileName)", font: monoFont, x: margin, y: &cursorY, context: context)
            cursorY -= 30
        }

        context.endPage()
        context.closePDF()

        pdfData.write(toFile: outputPath, atomically: true)
    }

    // Helper for PDF Text Drawing
    private func drawText(_ text: String, font: CTFont, x: CGFloat, y: inout CGFloat, context: CGContext, alignOnSameLine: Bool = false) {
        let pdfAlignmentOffset: CGFloat = 15
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let derivedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(derivedString)

        // Reset text matrix
        context.textMatrix = .identity

        // Core Graphics uses a bottom‑left origin and CoreText draws text relative to the
        // current text position's *baseline*. When `alignOnSameLine` is true we have just
        // drawn another element on this logical line (typically the timestamp) and now draw
        // the accompanying text. Because the timestamp and the main text can differ in font
        // metrics and are rendered with separate draw calls, their baselines do not naturally
        // line up and can visually overlap.
        //
        // `pdfAlignmentOffset` (currently 15 points) is an empirically chosen vertical nudge
        // that shifts the second draw upward so that the timestamp and its text appear on a
        // single visual line without colliding. If the PDF font sizes or line height change,
        // this constant can be adjusted to restore the intended baseline alignment.
        let textPositionY = alignOnSameLine ? y + pdfAlignmentOffset : y // Adjust y if we just drew a timestamp
        context.textPosition = CGPoint(x: x, y: textPositionY)
        CTLineDraw(line, context)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private func formatTimestampVTT(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds - Double(Int(seconds))) * 1000)

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }

}

// MARK: - Supporting Types

enum TranscriptionError: LocalizedError {
    case whisperKitNotFound
    case fileNotFound(String)
    case transcriptionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperKitNotFound:
            return "WhisperKit CLI not found. Please install it using Homebrew."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}

extension String {
    var deletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }
}
