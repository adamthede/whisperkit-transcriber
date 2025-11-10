//
//  TranscriptionManager.swift
//  WhisperKitTranscriber
//
//  Manages transcription state and coordinates WhisperKit CLI calls
//

import Foundation
import SwiftUI
import Combine

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
    @Published var enableDiarization = false
    @Published var diarizationServerURL = "http://localhost:50061/diarize"

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

        // Extract transcription text (after "Transcription of ..." line)
        let lines = output.components(separatedBy: .newlines)
        var transcriptionText = ""
        var foundTranscription = false

        for line in lines {
            if foundTranscription {
                transcriptionText += line + "\n"
            } else if line.hasPrefix("Transcription of") {
                foundTranscription = true
            }
        }

        transcriptionText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

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

        // Parse transcription into segments (basic implementation: split by sentences)
        var segments = parseTranscriptionIntoSegments(transcriptionText)

        // Perform diarization if enabled
        if enableDiarization {
            await MainActor.run {
                statusMessage = "Performing speaker diarization for \(audioFile.lastPathComponent)..."
            }

            do {
                // Update diarization server URL before running
                DiarizationManager.shared.updateServerURL(diarizationServerURL)

                let diarization = try await DiarizationManager.shared.diarize(audioFile: audioFile)

                // Merge diarization with transcription segments
                segments = DiarizationManager.shared.mergeDiarizationWithTranscription(
                    diarization: diarization,
                    transcriptionSegments: segments
                )

                print("✅ Diarization completed for \(audioFile.lastPathComponent)")
                print("   Found \(Set(segments.compactMap { $0.speaker }).count) unique speakers")
            } catch {
                // Log error but don't fail transcription
                print("⚠️ Diarization failed: \(error.localizedDescription)")
                await MainActor.run {
                    statusMessage = "Warning: Diarization failed, continuing with transcription only..."
                }
                // Continue with segments without speaker info
            }
        }

        return TranscriptionResult(
            sourcePath: audioFile.path,
            fileName: audioFile.lastPathComponent,
            text: transcriptionText,
            duration: duration,
            createdAt: Date(),
            modelUsed: modelUsed,
            segments: segments
        )
    }

    private func parseTranscriptionIntoSegments(_ text: String) -> [TranscriptionSegment] {
        // Simple segment parsing: split by sentences and estimate timestamps
        // This is a basic implementation - ideally we'd get this from WhisperKit CLI
        var segments: [TranscriptionSegment] = []

        // Split text into sentences (basic split on . ! ?)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Estimate timing (rough approximation: ~150 words per minute)
        let wordsPerSecond = 150.0 / 60.0
        var currentTime = 0.0

        for sentence in sentences {
            let words = sentence.split(separator: " ").count
            let estimatedDuration = Double(words) / wordsPerSecond

            let segment = TranscriptionSegment(
                startTime: currentTime,
                endTime: currentTime + estimatedDuration,
                text: sentence,
                speaker: nil,
                speakerName: nil
            )

            segments.append(segment)
            currentTime += estimatedDuration
        }

        return segments
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
            try exportMarkdown(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .plainText:
            try exportPlainText(transcriptions: transcriptions, outputPath: finalOutputPath)
        case .json:
            try exportJSON(transcriptions: transcriptions, outputPath: finalOutputPath)
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

    private func exportMarkdown(transcriptions: [TranscriptionResult], outputPath: String) throws {
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
                markdown += "*Duration: \(TranscriptionManager.formatDuration(duration))*\n\n"
            }

            // Export with speaker labels if available
            if transcription.hasSpeakers {
                for segment in transcription.segments {
                    if let speaker = segment.speaker {
                        let speakerName = transcription.speakerLabels[speaker] ?? speaker
                        markdown += "**\(speakerName)**: "
                    }
                    markdown += "\(segment.text)\n\n"
                }
            } else {
                markdown += "\(transcription.displayText)\n\n"
            }

            markdown += "---\n\n"
        }

        // Write to file
        try markdown.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private func exportPlainText(transcriptions: [TranscriptionResult], outputPath: String) throws {
        var text = "Combined Audio Transcription\n"
        text += "\(String(repeating: "=", count: 30))\n\n"

        for transcription in transcriptions {
            text += "\(transcription.fileName)\n"
            text += "\(String(repeating: "-", count: transcription.fileName.count))\n\n"
            if let duration = transcription.duration {
                text += "Duration: \(TranscriptionManager.formatDuration(duration))\n\n"
            }

            // Export with speaker labels if available
            if transcription.hasSpeakers {
                for segment in transcription.segments {
                    if let speaker = segment.speaker {
                        let speakerName = transcription.speakerLabels[speaker] ?? speaker
                        text += "[\(speakerName)]: "
                    }
                    text += "\(segment.text)\n\n"
                }
            } else {
                text += "\(transcription.displayText)\n\n"
            }

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
                var transcriptionDict: [String: Any] = [
                    "source_path": transcription.sourcePath,
                    "file_name": transcription.fileName,
                    "text": transcription.displayText,
                    "duration_seconds": transcription.duration as Any,
                    "created_at": formatter.string(from: transcription.createdAt),
                    "model_used": transcription.modelUsed as Any
                ]

                // Add speaker information if available
                if transcription.hasSpeakers {
                    transcriptionDict["has_speakers"] = true
                    transcriptionDict["speaker_labels"] = transcription.speakerLabels
                    transcriptionDict["segments"] = transcription.segments.map { segment in
                        [
                            "start_time": segment.startTime,
                            "end_time": segment.endTime,
                            "text": segment.text,
                            "speaker": segment.speaker as Any,
                            "speaker_name": segment.speakerName as Any
                        ]
                    }
                } else {
                    transcriptionDict["has_speakers"] = false
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
            if transcription.hasSpeakers {
                markdown += "has_speakers: true\n"
                markdown += "speakers: \(transcription.uniqueSpeakers.joined(separator: ", "))\n"
            }
            markdown += "---\n\n"
            markdown += "# \(baseFileName)\n\n"

            // Export with speaker labels if available
            if transcription.hasSpeakers {
                for segment in transcription.segments {
                    if let speaker = segment.speaker {
                        let speakerName = transcription.speakerLabels[speaker] ?? speaker
                        markdown += "**\(speakerName)**: "
                    }
                    markdown += "\(segment.text)\n\n"
                }
            } else {
                markdown += "\(transcription.displayText)\n"
            }

            try markdown.write(toFile: fileURL.path, atomically: true, encoding: .utf8)
        }
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

    var errorDescription: String? {
        switch self {
        case .whisperKitNotFound:
            return "WhisperKit CLI not found. Please ensure whisperkit-cli is installed and available in your PATH."
        case .transcriptionFailed(let details):
            return "Transcription failed: \(details)"
        }
    }
}

extension String {
    var deletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }
}

