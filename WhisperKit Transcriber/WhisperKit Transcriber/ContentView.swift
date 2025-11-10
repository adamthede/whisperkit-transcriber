//
//  ContentView.swift
//  WhisperKitTranscriber
//
//  Main UI view with drop zone, transcription preview, and export options
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation

struct ContentView: View {
    @StateObject private var transcriptionManager = TranscriptionManager()
    @State private var isDropTargeted = false
    @State private var selectedTranscription: TranscriptionResult?
    @State private var showFileList = false
    @State private var showConfiguration = true
    @State private var showResults = false
    @State private var exportFormat: ExportFormat = .markdown
    @State private var includeTimestampInFilename = true
    @State private var alsoExportIndividualFiles = false
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showSystemInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("WhisperKit Batch Transcriber")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)

                // Drop Zone
                dropZoneView
                    .padding(.horizontal)

                // File List (Expandable)
                if !transcriptionManager.audioFiles.isEmpty {
                    fileListView
                        .padding(.horizontal)
                }

                // Configuration Section (Expandable)
                configurationSection
                    .padding(.horizontal)

                // Start Button
                startButton
                    .padding(.horizontal)

                // Progress (when processing)
                if transcriptionManager.isProcessing {
                    progressView
                        .padding(.horizontal)
                }

                // Results Section (appears after transcription starts)
                if transcriptionManager.showResults {
                    resultsSection
                        .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Error", isPresented: $transcriptionManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transcriptionManager.errorMessage)
        }
        .alert("Export Successful", isPresented: $transcriptionManager.showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Transcription exported successfully!")
        }
        .sheet(isPresented: $showSystemInfo) {
            SystemInfoView()
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                        )
                )

            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                if transcriptionManager.audioFiles.isEmpty {
                    Text("Drag audio files here")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Select Directory") {
                        selectDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    VStack(spacing: 8) {
                        Text("\(transcriptionManager.audioFiles.count) file(s) selected")
                            .font(.headline)

                        Button("Change Selection") {
                            selectDirectory()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(30)
        }
        .frame(height: 210)
        .onDrop(of: [.audio, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - File List

    private var fileListView: some View {
        DisclosureGroup(isExpanded: $showFileList) {
            List {
                ForEach(transcriptionManager.audioFiles, id: \.self) { file in
                    FileRowView(
                        file: file,
                        status: transcriptionManager.fileStatuses.first(where: { $0.url == file }),
                        audioPlayer: audioPlayer,
                        statusIcon: statusIcon(for:),
                        statusColor: statusColor(for:),
                        formatDuration: formatDuration(_:)
                    )
                }
            }
            .frame(height: min(CGFloat(transcriptionManager.audioFiles.count) * 60, 300))
        } label: {
            Text("\(transcriptionManager.audioFiles.count) files selected")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        DisclosureGroup("Configuration", isExpanded: $showConfiguration) {
            VStack(alignment: .leading, spacing: 16) {
                // Model Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("", selection: $transcriptionManager.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    if transcriptionManager.selectedModel != .custom {
                        Text(transcriptionManager.selectedModel.info)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if transcriptionManager.selectedModel == .custom {
                        HStack {
                            TextField("Model path", text: $transcriptionManager.customModelPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                browseModelPath()
                            }
                        }
                    }
                }

                Divider()

                // Language
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("", selection: $transcriptionManager.selectedLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                // GPU/Compute Unit Configuration
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.purple)
                        Text("GPU Acceleration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button(action: {
                            showSystemInfo = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("System Info")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Audio Encoder Compute Unit
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Audio Encoder")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $transcriptionManager.audioEncoderComputeUnit) {
                            ForEach(ComputeUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)

                        if let warning = transcriptionManager.audioEncoderComputeUnit.compatibilityWarning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(warning)
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                        } else {
                            Text(transcriptionManager.audioEncoderComputeUnit.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Text Decoder Compute Unit
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text Decoder")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $transcriptionManager.textDecoderComputeUnit) {
                            ForEach(ComputeUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)

                        if let warning = transcriptionManager.textDecoderComputeUnit.compatibilityWarning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(warning)
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                        } else {
                            Text(transcriptionManager.textDecoderComputeUnit.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // WhisperKit Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("WhisperKit Installation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Text("This app requires WhisperKit CLI to be installed via Homebrew:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("brew install whisperkit-cli")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    Text("Once installed, the app will automatically find and use it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task {
                    await transcriptionManager.startTranscription()
                }
            }) {
                HStack {
                    if transcriptionManager.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                    Text(transcriptionManager.isProcessing ? "Transcribing..." : "Start Transcription")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(transcriptionManager.audioFiles.isEmpty || transcriptionManager.isProcessing)

            // Reset button - only show when not processing and has results
            if !transcriptionManager.isProcessing && (!transcriptionManager.completedTranscriptions.isEmpty || !transcriptionManager.audioFiles.isEmpty) {
                Button(action: {
                    audioPlayer.stop()
                    transcriptionManager.reset()
                }) {
                    Text("Clear & Start New")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text("Transcribing...")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            ProgressView(value: transcriptionManager.progress)
                .progressViewStyle(.linear)

            Text(transcriptionManager.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if !transcriptionManager.completedTranscriptions.isEmpty {
                Text("✓ \(transcriptionManager.completedTranscriptions.count) file(s) completed")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        DisclosureGroup("Transcription Results", isExpanded: $showResults) {
            if transcriptionManager.completedTranscriptions.isEmpty && !transcriptionManager.isProcessing {
                Text("No transcriptions yet. Start transcription to see results here.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    // Summary
                    HStack {
                        Text("\(transcriptionManager.completedTranscriptions.count) of \(transcriptionManager.audioFiles.count) completed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // Transcription List
                    if !transcriptionManager.completedTranscriptions.isEmpty {
                        transcriptionListView
                    }

                    // Preview/Edit Area
                    if let selected = selectedTranscription {
                        transcriptionDetailView(selected)
                    }

                    // Export Options
                    if !transcriptionManager.completedTranscriptions.isEmpty {
                        exportOptionsView
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var transcriptionListView: some View {
        List(selection: $selectedTranscription) {
            ForEach(transcriptionManager.completedTranscriptions) { transcription in
                TranscriptionRow(transcription: transcription)
                    .tag(transcription)
            }
        }
        .frame(height: 200)
        .listStyle(.sidebar)
    }

    private func transcriptionDetailView(_ transcription: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(transcription.fileName)
                .font(.headline)

            // Metadata and performance metrics
            VStack(alignment: .leading, spacing: 6) {
                if let duration = transcription.duration {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Audio Duration: \(formatDuration(duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let transcriptionDuration = transcription.transcriptionDuration {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Transcription Time: \(String(format: "%.2f", transcriptionDuration))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let realTimeFactor = transcription.realTimeFactor {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(realTimeFactor >= 1.0 ? .green : .orange)
                            .frame(width: 20)
                        Text("Speed: \(String(format: "%.2fx", realTimeFactor)) real-time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if realTimeFactor >= 2.0 {
                            Text("(Fast)")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if realTimeFactor < 1.0 {
                            Text("(Slower than real-time)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                if let audioEncoder = transcription.audioEncoderComputeUnit {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        Text("Audio Encoder: \(formatComputeUnit(audioEncoder))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let textDecoder = transcription.textDecoderComputeUnit {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        Text("Text Decoder: \(formatComputeUnit(textDecoder))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            TextEditor(text: Binding(
                get: { transcription.displayText },
                set: { newValue in
                    transcriptionManager.updateTranscription(transcription, editedText: newValue)
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(height: 200)
            .border(Color.secondary.opacity(0.2))
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var exportOptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.headline)

            HStack {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)

                Button("Export...") {
                    exportTranscriptions()
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include timestamp in filename", isOn: $includeTimestampInFilename)
                    .font(.caption)

                if exportFormat != .individualFiles {
                    Toggle("Also export individual files", isOn: $alsoExportIndividualFiles)
                        .font(.caption)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Helper Views

    struct FileRowView: View {
        let file: URL
        let status: FileStatus?
        @ObservedObject var audioPlayer: AudioPlayerManager
        let statusIcon: (FileStatus.ProcessingStatus?) -> String
        let statusColor: (FileStatus.ProcessingStatus?) -> Color
        let formatDuration: (Int) -> String

        @State private var fileSize: String?
        @State private var audioDuration: TimeInterval?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: statusIcon(status?.status))
                        .foregroundColor(statusColor(status?.status))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            if let size = fileSize {
                                Label(size, systemImage: "doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let duration = audioDuration {
                                Label(formatDuration(Int(duration)), systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if let transcriptionDuration = status?.transcription?.duration {
                                Label(formatDuration(transcriptionDuration), systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Play button
                    Button(action: {
                        if audioPlayer.isPlaying && audioPlayer.currentFile == file {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.play(file: file)
                        }
                    }) {
                        Image(systemName: audioPlayer.isPlaying && audioPlayer.currentFile == file ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(status?.status == .processing)
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                loadFileMetadata()
            }
        }

        private func loadFileMetadata() {
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? Int64 {
                fileSize = formatFileSize(size)
            }

            // Get audio duration using AVFoundation
            Task {
                let duration = await getAudioDuration(from: file)
                await MainActor.run {
                    audioDuration = duration
                }
            }
        }

        private func formatFileSize(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }

        private func getAudioDuration(from url: URL) async -> TimeInterval? {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                return CMTimeGetSeconds(duration)
            } catch {
                return nil
            }
        }
    }

    struct TranscriptionRow: View {
        let transcription: TranscriptionResult

        var body: some View {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcription.fileName)
                        .font(.subheadline)
                    Text(transcription.preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let duration = transcription.duration {
                    Text(ContentView.formatDuration(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helper Functions

    private func statusIcon(for status: FileStatus.ProcessingStatus?) -> String {
        switch status {
        case .pending: return "clock"
        case .processing: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .none: return "doc"
        }
    }

    private func statusColor(for status: FileStatus.ProcessingStatus?) -> Color {
        switch status {
        case .pending: return .secondary
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .none: return .secondary
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
        return ContentView.formatDuration(seconds)
    }

    private func formatComputeUnit(_ rawValue: String) -> String {
        switch rawValue {
        case "all":
            return "All (CPU + GPU + Neural Engine)"
        case "cpuAndGPU":
            return "CPU + GPU"
        case "cpuAndNeuralEngine":
            return "CPU + Neural Engine"
        case "cpuOnly":
            return "CPU Only"
        default:
            return rawValue
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                transcriptionManager.loadAudioFiles(from: url)
            }
        }
    }

    private func browseModelPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                transcriptionManager.customModelPath = url.path
            }
        }
    }

    private func exportTranscriptions() {
        if exportFormat == .individualFiles {
            // For individual files, use NSOpenPanel to select a directory
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose Folder"
            panel.message = "Select a folder to save individual transcription files"

            if panel.runModal() == .OK {
                if let url = panel.url {
                    do {
                        try transcriptionManager.exportTranscriptions(
                            format: exportFormat,
                            outputPath: url.path,
                            includeTimestamp: includeTimestampInFilename,
                            alsoExportIndividual: alsoExportIndividualFiles
                        )
                        transcriptionManager.showSuccess = true
                    } catch {
                        transcriptionManager.showError(message: "Export failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // For single file exports, use NSSavePanel
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension)!]
            panel.nameFieldStringValue = "transcription.\(exportFormat.fileExtension)"
            panel.canCreateDirectories = true

            if panel.runModal() == .OK {
                if let url = panel.url {
                    do {
                        try transcriptionManager.exportTranscriptions(
                            format: exportFormat,
                            outputPath: url.path,
                            includeTimestamp: includeTimestampInFilename,
                            alsoExportIndividual: alsoExportIndividualFiles
                        )
                        transcriptionManager.showSuccess = true
                    } catch {
                        transcriptionManager.showError(message: "Export failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    defer { group.leave() }
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                if urls.count == 1 && urls[0].hasDirectoryPath {
                    transcriptionManager.loadAudioFiles(from: urls[0])
                } else {
                    var audioFiles: [URL] = []
                    for url in urls {
                        if url.hasDirectoryPath {
                            audioFiles.append(contentsOf: transcriptionManager.findAudioFiles(in: url))
                        } else if transcriptionManager.isAudioFile(url) {
                            audioFiles.append(url)
                        }
                    }
                    transcriptionManager.audioFiles = audioFiles
                }
            }
        }

        return true
    }
}

#Preview {
    ContentView()
}
