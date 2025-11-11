//
//  TranscriptionManager.swift
//  WhisperKitTranscriber
//
//  Manages transcription state and coordinates WhisperKit CLI calls
//

import Foundation
import SwiftUI
import Combine
import AppKit
import PDFKit

class TranscriptionManager: ObservableObject {
    @Published var audioFiles: [URL] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
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

    private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]

    func reset() {
        audioFiles = []
        completedTranscriptions = []
        fileStatuses = []
        isProcessing = false
        progress = 0.0
        statusMessage = ""
        showError = false
        errorMessage = ""
        showSuccess = false
        showResults = false
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
        return supportedAudioExtensions.contains(pathExtension)
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
                let currentProgress = Double(index) / totalFiles
                progress = currentProgress
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
                    }
                }
            } catch {
                let errorMsg = error.localizedDescription
                print("Error transcribing \(audioFile.lastPathComponent): \(errorMsg)")

                // Update file status to failed on main actor
                await MainActor.run {
                    if let statusIndex = fileStatuses.firstIndex(where: { $0.url == audioFile }) {
                        fileStatuses[statusIndex].status = .failed(errorMsg)
                    }
                }
            }

            // Yield periodically to keep UI responsive
            await Task.yield()
        }

        await MainActor.run {
            if successfulTranscriptions.isEmpty {
                showError(message: "No files were successfully transcribed. Please check the errors above.")
            }
            isProcessing = false
            progress = 1.0
            statusMessage = "Transcription complete: \(successfulTranscriptions.count) of \(audioFiles.count) files"
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

        print("🎤 Transcribing: \(audioFile.lastPathComponent)")
        print("   Using: \(whisperkitPath)")

        // Build command
        var arguments: [String] = [
            "transcribe",
            "--audio-path", audioFile.path,
            "--language", selectedLanguage.code,
            "--verbose"
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

            func append(_ text: String) {
                buffer += text
                let allLines = buffer.components(separatedBy: .newlines)
                buffer = allLines.last ?? ""

                for line in allLines.dropLast() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
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

        let collector = OutputCollector()

        // Read output in real-time with proper handling
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF reached
                return
            }

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

        let output: String
        do {
            try process.run()

            // Update status to show we're processing (on main actor)
            await MainActor.run {
                statusMessage = "Processing \(audioFile.lastPathComponent)..."
            }

            // Wait for process to complete with timeout
            actor ProcessState {
                private(set) var exited = false

                func markExited() {
                    exited = true
                }
            }

            let processState = ProcessState()

            let waitTask = Task {
                process.waitUntilExit()
                await processState.markExited()
            }

            // Wait for process with timeout (30 minutes max per file)
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 1_800_000_000_000) // 30 minutes
            }

            // Race: wait for either process completion or timeout
            // Poll periodically and yield to keep UI responsive
            var didTimeout: Bool = false

            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    // Poll for process completion, yielding frequently
                    while process.isRunning {
                        await Task.yield() // Yield to UI every iteration
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                    return false // Process finished normally
                }
                group.addTask {
                    _ = await timeoutTask.result
                    return true // Timeout occurred
                }

                if let result = await group.next() {
                    didTimeout = result
                    if didTimeout {
                        // Timeout occurred
                        waitTask.cancel()
                    } else {
                        // Process finished
                        timeoutTask.cancel()
                    }
                } else {
                    didTimeout = false
                    timeoutTask.cancel()
                }
            }

            // Wait for waitTask to complete (should be quick now)
            _ = await waitTask.result

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
                let exited = await processState.exited
                if !exited {
                    process.terminate() // Force terminate if still running
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

            // Get any remaining output
            let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
            if let remainingText = String(data: remainingData, encoding: .utf8), !remainingText.isEmpty {
                await collector.addRemaining(remainingText)
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

        // Try to parse timestamp information from verbose output
        let (transcriptionText, realSegments) = parseTranscriptionOutput(output)

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

        if let segments = realSegments, !segments.isEmpty {
            print("✅ Extracted \(segments.count) segments with real timestamps")
        }

        return TranscriptionResult(
            sourcePath: audioFile.path,
            fileName: audioFile.lastPathComponent,
            text: transcriptionText,
            duration: duration,
            createdAt: Date(),
            modelUsed: modelUsed,
            realSegments: realSegments
        )
    }

    private func parseTranscriptionOutput(_ output: String) -> (String, [TranscriptionSegment]?) {
        let lines = output.components(separatedBy: .newlines)
        var transcriptionText = ""
        var foundTranscription = false
        var segments: [TranscriptionSegment] = []

        // Try to detect timestamp format: [00:00.000 --> 00:05.000] text
        let timestampPattern = #"\[(\d+:\d+\.\d+)\s*-->\s*(\d+:\d+\.\d+)\]\s*(.+)"#
        let timestampRegex = try? NSRegularExpression(pattern: timestampPattern, options: [])

        for line in lines {
            if foundTranscription {
                // Try to parse line with timestamps
                if let regex = timestampRegex,
                   let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                    // Extract timestamp and text
                    if let startRange = Range(match.range(at: 1), in: line),
                       let endRange = Range(match.range(at: 2), in: line),
                       let textRange = Range(match.range(at: 3), in: line) {
                        let startTimeStr = String(line[startRange])
                        let endTimeStr = String(line[endRange])
                        let text = String(line[textRange])

                        if let startTime = parseTimestamp(startTimeStr),
                           let endTime = parseTimestamp(endTimeStr) {
                            segments.append(TranscriptionSegment(
                                startTime: startTime,
                                endTime: endTime,
                                text: text
                            ))
                        }

                        transcriptionText += text + "\n"
                    }
                } else {
                    // No timestamp, just add the text
                    transcriptionText += line + "\n"
                }
            } else if line.hasPrefix("Transcription of") {
                foundTranscription = true
            }
        }

        transcriptionText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only return segments if we found at least some
        let realSegments = segments.isEmpty ? nil : segments
        return (transcriptionText, realSegments)
    }

    private func parseTimestamp(_ timeStr: String) -> Double? {
        // Parse format: MM:SS.mmm or HH:MM:SS.mmm
        let components = timeStr.components(separatedBy: ":")

        if components.count == 2 {
            // MM:SS.mmm
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else {
                return nil
            }
            return minutes * 60 + seconds
        } else if components.count == 3 {
            // HH:MM:SS.mmm
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else {
                return nil
            }
            return hours * 3600 + minutes * 60 + seconds
        }

        return nil
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

    func exportTranscriptions(format: ExportFormat, outputPath: String, includeTimestamp: Bool = true, alsoExportIndividual: Bool = false, includeTimestampsInContent: Bool = true) throws {
        let transcriptions = completedTranscriptions

        // Add timestamp to filename if requested
        let finalOutputPath = includeTimestamp && format != .individualFiles ? addTimestampToFilename(outputPath, format: format) : outputPath

        switch format {
        case .markdown:
            try exportMarkdown(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamps: includeTimestampsInContent)
        case .plainText:
            try exportPlainText(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamps: includeTimestampsInContent)
        case .json:
            try exportJSON(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamps: includeTimestampsInContent)
        case .srt:
            try exportSRT(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .vtt:
            try exportVTT(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .html:
            try exportHTML(transcriptions: transcriptions, outputPath: finalOutputPath, includeTimestamps: includeTimestampsInContent)
        case .docx:
            try exportDOCX(transcriptions: transcriptions, outputPath: finalOutputPath)
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

    private func exportMarkdown(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamps: Bool = false) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var markdown = ""

        // YAML front matter
        markdown += "---\n"
        markdown += "combined_from: \(transcriptions.count) files\n"
        markdown += "created_utc: \"\(formatter.string(from: Date()))\"\n"
        markdown += "format: combined_markdown\n"
        markdown += "includes_timestamps: \(includeTimestamps)\n"
        markdown += "---\n\n"

        markdown += "# Combined Audio Transcription\n\n"

        // Add each transcription
        for transcription in transcriptions {
            let fileName = (transcription.fileName as NSString).deletingPathExtension
            markdown += "## \(fileName)\n\n"

            // Add metadata if available
            if let duration = transcription.duration {
                markdown += "*Duration: \(TranscriptionManager.formatDuration(duration))*\n"
                if includeTimestamps && transcription.hasRealTimestamps {
                    markdown += " *(Real timestamps)*"
                }
                markdown += "\n\n"
            }

            // Include timestamped segments if requested
            if includeTimestamps {
                let segments = transcription.segments
                for segment in segments {
                    let startTime = TranscriptionManager.formatDuration(Int(segment.startTime))
                    let endTime = TranscriptionManager.formatDuration(Int(segment.endTime))
                    markdown += "`[\(startTime) - \(endTime)]` \(segment.text)\n\n"
                }
            } else {
                markdown += "\(transcription.displayText)\n\n"
            }

            markdown += "---\n\n"
        }

        // Write to file
        try markdown.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportPlainText(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamps: Bool = false) throws {
        var text = "Combined Audio Transcription\n"
        text += "\(String(repeating: "=", count: 30))\n\n"

        for transcription in transcriptions {
            text += "\(transcription.fileName)\n"
            text += "\(String(repeating: "-", count: transcription.fileName.count))\n\n"
            if let duration = transcription.duration {
                text += "Duration: \(TranscriptionManager.formatDuration(duration))"
                if includeTimestamps && transcription.hasRealTimestamps {
                    text += " (Real timestamps)"
                }
                text += "\n\n"
            }

            // Include timestamped segments if requested
            if includeTimestamps {
                let segments = transcription.segments
                for segment in segments {
                    let startTime = TranscriptionManager.formatDuration(Int(segment.startTime))
                    let endTime = TranscriptionManager.formatDuration(Int(segment.endTime))
                    text += "[\(startTime) - \(endTime)] \(segment.text)\n"
                }
            } else {
                text += "\(transcription.displayText)\n"
            }

            text += "\n\(String(repeating: "-", count: 50))\n\n"
        }

        try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportJSON(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamps: Bool = false) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let jsonObject: [String: Any] = [
            "metadata": [
                "combined_from": transcriptions.count,
                "created_utc": formatter.string(from: Date()),
                "format": "json",
                "includes_timestamps": includeTimestamps
            ],
            "transcriptions": transcriptions.map { transcription in
                var transcriptionDict: [String: Any] = [
                    "source_path": transcription.sourcePath,
                    "file_name": transcription.fileName,
                    "text": transcription.displayText,
                    "duration_seconds": transcription.duration as Any,
                    "created_at": formatter.string(from: transcription.createdAt),
                    "model_used": transcription.modelUsed as Any,
                    "has_real_timestamps": transcription.hasRealTimestamps
                ]

                // Include segments if timestamps requested
                if includeTimestamps {
                    let segments = transcription.segments
                    transcriptionDict["segments"] = segments.map { segment in
                        [
                            "start_time": segment.startTime,
                            "end_time": segment.endTime,
                            "text": segment.text,
                            "speaker": segment.speaker as Any
                        ]
                    }
                }

                return transcriptionDict
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
        try jsonData.write(to: URL(fileURLWithPath: outputPath))
    }

    private func exportIndividualFiles(transcriptions: [TranscriptionResult], outputDir: String, includeTimestamp: Bool = false) throws {
        let outputURL = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let batchTimestamp = timestampFormatter.string(from: Date())

        for transcription in transcriptions {
            let baseFileName = (transcription.fileName as NSString).deletingPathExtension
            let fileName: String
            if includeTimestamp {
                fileName = "\(batchTimestamp)_\(baseFileName).md"
            } else {
                fileName = baseFileName + ".md"
            }
            let fileURL = outputURL.appendingPathComponent(fileName)

            var markdown = "---\n"
            markdown += "source_path: \"\(transcription.sourcePath)\"\n"
            markdown += "created_utc: \"\(ISO8601DateFormatter().string(from: transcription.createdAt))\"\n"
            if let duration = transcription.duration {
                markdown += "duration_seconds: \(duration)\n"
            }
            if let model = transcription.modelUsed {
                markdown += "model_used: \"\(model)\"\n"
            }
            markdown += "---\n\n"
            markdown += "# \(baseFileName)\n\n"
            markdown += "\(transcription.displayText)\n"

            try markdown.write(toFile: fileURL.path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - SRT Export

    private func exportSRT(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var srtContent = ""
        var subtitleIndex = 1

        for transcription in transcriptions {
            let segments = transcription.segments

            for segment in segments {
                // SRT format: index, timestamps, text, blank line
                srtContent += "\(subtitleIndex)\n"
                srtContent += "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n"
                srtContent += "\(segment.text)\n\n"
                subtitleIndex += 1
            }
        }

        try srtContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func formatSRTTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }

    // MARK: - VTT Export

    private func exportVTT(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var vttContent = "WEBVTT\n\n"

        for transcription in transcriptions {
            // Add file identifier as NOTE
            let fileName = (transcription.fileName as NSString).deletingPathExtension
            vttContent += "NOTE \(fileName)\n\n"

            let segments = transcription.segments

            for segment in segments {
                vttContent += "\(formatVTTTime(segment.startTime)) --> \(formatVTTTime(segment.endTime))\n"
                vttContent += "\(segment.text)\n\n"
            }
        }

        try vttContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func formatVTTTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)

        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }

    // MARK: - HTML Export

    private func exportHTML(transcriptions: [TranscriptionResult], outputPath: String, includeTimestamps: Bool = false) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Audio Transcription</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 20px;
                    line-height: 1.6;
                    color: #333;
                }
                h1 {
                    color: #333;
                    border-bottom: 2px solid #333;
                    padding-bottom: 10px;
                    margin-bottom: 20px;
                }
                h2 {
                    color: #666;
                    margin-top: 30px;
                    margin-bottom: 15px;
                }
                .metadata {
                    color: #888;
                    font-size: 0.9em;
                    margin-bottom: 20px;
                }
                .transcription {
                    line-height: 1.6;
                    margin-bottom: 30px;
                }
                .segment {
                    margin-bottom: 10px;
                }
                .timestamp {
                    color: #0066cc;
                    font-family: monospace;
                    font-size: 0.85em;
                    margin-right: 8px;
                }
                .separator {
                    border-top: 1px solid #ddd;
                    margin: 30px 0;
                }
                @media (prefers-color-scheme: dark) {
                    body { background-color: #1e1e1e; color: #d4d4d4; }
                    h1 { color: #d4d4d4; border-bottom-color: #555; }
                    h2 { color: #b0b0b0; }
                    .metadata { color: #808080; }
                    .timestamp { color: #4d9fff; }
                    .separator { border-top-color: #555; }
                }
            </style>
        </head>
        <body>
            <h1>Combined Audio Transcription</h1>
            <div class="metadata">
                <p>Generated: \(formatter.string(from: Date()))</p>
                <p>Files: \(transcriptions.count)</p>
                <p>Timestamps: \(includeTimestamps ? "Included" : "Not included")</p>
            </div>

        """

        for transcription in transcriptions {
            let fileName = (transcription.fileName as NSString).deletingPathExtension
            html += "<div class=\"transcription\">\n"
            html += "<h2>\(escapeHTML(fileName))</h2>\n"

            if let duration = transcription.duration {
                html += "<div class=\"metadata\">Duration: \(TranscriptionManager.formatDuration(duration))"
                if includeTimestamps && transcription.hasRealTimestamps {
                    html += " (Real timestamps)"
                }
                html += "</div>\n"
            }

            // Include timestamped segments if requested
            if includeTimestamps {
                let segments = transcription.segments
                for segment in segments {
                    let startTime = TranscriptionManager.formatDuration(Int(segment.startTime))
                    let endTime = TranscriptionManager.formatDuration(Int(segment.endTime))
                    html += "<div class=\"segment\">\n"
                    html += "<span class=\"timestamp\">[\(startTime) - \(endTime)]</span>\n"
                    html += "<span>\(escapeHTML(segment.text))</span>\n"
                    html += "</div>\n"
                }
            } else {
                // Escape HTML entities and convert newlines to <br>
                let escapedText = escapeHTML(transcription.displayText)
                    .replacingOccurrences(of: "\n", with: "<br>\n")
                html += "<p>\(escapedText)</p>\n"
            }

            html += "</div>\n"
            html += "<div class=\"separator\"></div>\n"
        }

        html += """
        </body>
        </html>
        """

        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - DOCX Export

    private func exportDOCX(transcriptions: [TranscriptionResult], outputPath: String) throws {
        // Try to export using Python's python-docx library
        // If that fails, fallback to RTF format
        do {
            try exportDOCXViaPython(transcriptions: transcriptions, outputPath: outputPath)
        } catch {
            print("⚠️ Python DOCX export failed: \(error.localizedDescription)")
            print("   Falling back to RTF format (compatible with Word)")

            // Fallback to RTF format
            let rtfPath = (outputPath as NSString).deletingPathExtension + ".rtf"
            try exportRTF(transcriptions: transcriptions, outputPath: rtfPath)

            // If original path was .docx, inform user
            if outputPath.hasSuffix(".docx") {
                print("   Exported as RTF instead: \(rtfPath)")
            }
        }
    }

    private func exportDOCXViaPython(transcriptions: [TranscriptionResult], outputPath: String) throws {
        // Create temporary JSON file with transcription data
        let tempJSON = NSTemporaryDirectory() + UUID().uuidString + ".json"
        defer {
            try? FileManager.default.removeItem(atPath: tempJSON)
        }

        try exportJSON(transcriptions: transcriptions, outputPath: tempJSON)

        // Python script to convert JSON to DOCX
        let pythonScript = """
        import json
        import sys
        try:
            from docx import Document
            from docx.shared import Pt, Inches
        except ImportError:
            print("ERROR: python-docx not installed", file=sys.stderr)
            sys.exit(1)

        with open('\(tempJSON)', 'r') as f:
            data = json.load(f)

        doc = Document()

        # Title
        title = doc.add_heading('Combined Audio Transcription', 0)

        # Metadata
        metadata = data.get('metadata', {})
        p = doc.add_paragraph()
        p.add_run(f"Generated: {metadata.get('created_utc', 'N/A')}").font.size = Pt(9)
        p.add_run(f"\\nFiles: {metadata.get('combined_from', 0)}").font.size = Pt(9)

        # Transcriptions
        for trans in data.get('transcriptions', []):
            doc.add_heading(trans['file_name'], level=1)

            if trans.get('duration_seconds'):
                duration = trans['duration_seconds']
                hours = duration // 3600
                minutes = (duration % 3600) // 60
                secs = duration % 60
                if hours > 0:
                    duration_str = f"{hours}:{minutes:02d}:{secs:02d}"
                else:
                    duration_str = f"{minutes}:{secs:02d}"
                p = doc.add_paragraph(f"Duration: {duration_str}")
                p.runs[0].font.size = Pt(9)

            doc.add_paragraph(trans['text'])
            doc.add_page_break()

        doc.save('\(outputPath)')
        """

        // Execute Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", pythonScript]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.exportFailed("DOCX export failed: \(errorMessage)")
        }
    }

    private func exportRTF(transcriptions: [TranscriptionResult], outputPath: String) throws {
        let attributedString = NSMutableAttributedString()

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        attributedString.append(NSAttributedString(string: "Combined Audio Transcription\n\n", attributes: titleAttributes))

        // Metadata
        let metadataAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        attributedString.append(NSAttributedString(
            string: "Generated: \(formatter.string(from: Date()))\nFiles: \(transcriptions.count)\n\n",
            attributes: metadataAttributes
        ))

        // Content
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]

        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]

        for transcription in transcriptions {
            let fileName = (transcription.fileName as NSString).deletingPathExtension

            // File name heading
            attributedString.append(NSAttributedString(string: "\n\(fileName)\n", attributes: headingAttributes))

            // Duration if available
            if let duration = transcription.duration {
                attributedString.append(NSAttributedString(
                    string: "Duration: \(TranscriptionManager.formatDuration(duration))\n\n",
                    attributes: metadataAttributes
                ))
            }

            // Transcription text
            attributedString.append(NSAttributedString(string: "\(transcription.displayText)\n\n", attributes: bodyAttributes))

            // Separator
            attributedString.append(NSAttributedString(string: String(repeating: "─", count: 50) + "\n\n", attributes: metadataAttributes))
        }

        // Convert to RTF
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        try rtfData.write(to: URL(fileURLWithPath: outputPath))
    }

    // MARK: - PDF Export

    private func exportPDF(transcriptions: [TranscriptionResult], outputPath: String) throws {
        let pageWidth: CGFloat = 612.0  // 8.5 inches * 72 points/inch
        let pageHeight: CGFloat = 792.0  // 11 inches * 72 points/inch
        let margin: CGFloat = 72.0  // 1 inch margin
        let contentWidth = pageWidth - (2 * margin)

        // Create attributed string with all content
        let attributedString = NSMutableAttributedString()

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        attributedString.append(NSAttributedString(string: "Combined Audio Transcription\n\n", attributes: titleAttributes))

        // Metadata
        let metadataAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        attributedString.append(NSAttributedString(
            string: "Generated: \(formatter.string(from: Date()))\nFiles: \(transcriptions.count)\n\n",
            attributes: metadataAttributes
        ))

        // Content
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]

        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]

        for transcription in transcriptions {
            let fileName = (transcription.fileName as NSString).deletingPathExtension

            // File name heading
            attributedString.append(NSAttributedString(string: "\n\(fileName)\n", attributes: headingAttributes))

            // Duration if available
            if let duration = transcription.duration {
                attributedString.append(NSAttributedString(
                    string: "Duration: \(TranscriptionManager.formatDuration(duration))\n\n",
                    attributes: metadataAttributes
                ))
            }

            // Transcription text
            attributedString.append(NSAttributedString(string: "\(transcription.displayText)\n\n", attributes: bodyAttributes))

            // Separator
            attributedString.append(NSAttributedString(string: "─" + String(repeating: "─", count: 50) + "\n", attributes: metadataAttributes))
        }

        // Create PDF data
        let pdfData = NSMutableData()
        let pdfConsumer = CGDataConsumer(data: pdfData as CFMutableData)!

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)!

        // Render the attributed string into the PDF
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        var currentRange = CFRange(location: 0, length: 0)
        var currentPage = 0
        let textRect = CGRect(x: margin, y: margin, width: contentWidth, height: pageHeight - (2 * margin))

        while currentRange.location < attributedString.length {
            pdfContext.beginPage(mediaBox: &mediaBox)

            let framePath = CGPath(rect: textRect, transform: nil)
            let frameRange = CFRange(location: currentRange.location, length: attributedString.length - currentRange.location)
            let frame = CTFramesetterCreateFrame(framesetter, frameRange, framePath, nil)

            // Flip coordinates for PDF (origin at bottom-left)
            pdfContext.saveGState()
            pdfContext.translateBy(x: 0, y: pageHeight)
            pdfContext.scaleBy(x: 1.0, y: -1.0)
            CTFrameDraw(frame, pdfContext)
            pdfContext.restoreGState()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            currentRange.length = attributedString.length - currentRange.location

            pdfContext.endPage()
            currentPage += 1

            if visibleRange.length == 0 {
                break // Prevent infinite loop
            }
        }

        pdfContext.closePDF()

        // Write to file
        try pdfData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        return TranscriptionManager.formatDuration(seconds)
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
}

// MARK: - Supporting Types

enum TranscriptionError: LocalizedError {
    case whisperKitNotFound
    case transcriptionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperKitNotFound:
            return "WhisperKit CLI not found. Please ensure whisperkit-cli is installed and available in your PATH."
        case .transcriptionFailed(let details):
            return "Transcription failed: \(details)"
        case .exportFailed(let details):
            return "Export failed: \(details)"
        }
    }
}

extension String {
    var deletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }
}

