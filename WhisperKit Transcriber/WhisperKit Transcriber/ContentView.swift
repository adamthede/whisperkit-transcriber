
//
//  ContentView.swift
//  WhisperKitTranscriber
//
//  Main SwiftUI view for the WhisperKit Transcriber app. Manages drag-and-drop
//  and directory selection for audio/video files, coordinates transcription,
//  playback, and export options, and hosts subviews such as DropZoneCard and
//  ControlPanelCard. Redesigned with Mid-Century Modern aesthetics.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation

struct ContentView: View {
    @StateObject private var transcriptionManager = TranscriptionManager()
    @State private var isDropTargeted = false
    @State private var selectedTranscription: TranscriptionResult?
    @State private var showConfiguration = true
    // showFileList and showResults are implicit in the new feed design, but kept if needed for logic
    @State private var selectedExportFormats: Set<ExportFormat> = [.markdown]
    @State private var includeTimestampInFilename = true
    @State private var alsoExportIndividualFiles = false

    @StateObject private var audioPlayer = AudioPlayerManager()

    // Video Player State
    struct VideoSelection: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var videoSelection: VideoSelection?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    Text("WhisperKit Transcriber")
                        .font(Theme.headerFont())
                        .foregroundColor(Theme.text)
                        .padding(.top, 32)

                    // Hero Drop Zone
                    DropZoneCard(
                        isDropTargeted: isDropTargeted,
                        fileCount: transcriptionManager.audioFiles.count,
                        onSelectDirectory: selectDirectory
                    )
                    .onDrop(of: [.audio, .fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers: providers)
                    }
                    .padding(.horizontal, Theme.padding)

                    // Action Button (Start / Progress / Reset)
                    ActionBar(
                        isProcessing: transcriptionManager.isProcessing,
                        progress: transcriptionManager.progress,
                        batchProgress: transcriptionManager.batchProgress,
                        statusMessage: transcriptionManager.statusMessage,
                        completedCount: transcriptionManager.processedFileCount,
                        totalCount: transcriptionManager.audioFiles.count,
                        hasFiles: !transcriptionManager.audioFiles.isEmpty,
                        hasResults: !transcriptionManager.completedTranscriptions.isEmpty,
                        onStart: {
                            transcriptionManager.startTranscription()
                        },
                        onReset: {
                             audioPlayer.stop()
                             transcriptionManager.reset()
                        },
                        onCancel: transcriptionManager.cancelTranscription
                    )
                    .padding(.horizontal, Theme.padding)

                    // Transcription Feed
                    if !transcriptionManager.audioFiles.isEmpty {
                        TranscriptionFeed(
                            audioFiles: transcriptionManager.audioFiles,
                            completedTranscriptions: transcriptionManager.completedTranscriptions,
                            fileStatuses: transcriptionManager.fileStatuses,
                            audioPlayer: audioPlayer,
                            onPlayVideo: { url in
                                audioPlayer.pause()
                                videoSelection = VideoSelection(url: url)
                            },
                            transcriptionManager: transcriptionManager
                        )
                        .padding(.horizontal, Theme.padding)
                    }

                    // Export/Configuration Panel (Moved to bottom)
                    if !transcriptionManager.audioFiles.isEmpty {
                        // "Export options are all gray until the transcribing finishes"
                        // Exports are only enabled once processing has stopped and at least one transcription has completed.
                        let isExportEnabled = !transcriptionManager.isProcessing && !transcriptionManager.completedTranscriptions.isEmpty

                        ControlPanelCard(
                            selectedModel: $transcriptionManager.selectedModel,
                            customModelPath: $transcriptionManager.customModelPath,
                            selectedLanguage: $transcriptionManager.selectedLanguage,
                            selectedExportFormats: $selectedExportFormats,
                            includeTimestampInFilename: $includeTimestampInFilename,
                            alsoExportIndividualFiles: $alsoExportIndividualFiles,
                            onBrowseModel: browseModelPath,
                            onExport: exportTranscriptions,
                            isEnabled: isExportEnabled
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, Theme.padding)
                        .opacity(isExportEnabled ? 1.0 : 0.6)
                        .grayscale(isExportEnabled ? 0.0 : 1.0)
                        .disabled(!isExportEnabled)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
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
        .sheet(item: $videoSelection) { selection in
            if let transcription = transcriptionManager.completedTranscriptions.first(where: { $0.sourcePath == selection.url.path }) {
                VideoPlayerView(videoURL: selection.url, transcription: transcription)
            } else {
                VideoPlayerView(videoURL: selection.url, transcription: nil)
            }
        }
    }

    // MARK: - Logic Helpers (Kept from original)

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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Export Directory"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    for format in selectedExportFormats {
                        let extensionName = format.fileExtension
                        let outputFilename = "transcriptions.\(extensionName)"
                        let outputPath = url.path + "/" + outputFilename

                        try transcriptionManager.exportTranscriptions(
                            format: format,
                            outputPath: outputPath,
                            includeTimestamp: includeTimestampInFilename,
                            alsoExportIndividual: false
                        )

                        if alsoExportIndividualFiles && format != .individualFiles {
                             let individualDirKey = outputFilename + "_individual"
                             let individualDir = url.appendingPathComponent(individualDirKey).path
                             try transcriptionManager.exportIndividualFiles(
                                transcriptions: transcriptionManager.completedTranscriptions,
                                outputDir: individualDir,
                                includeTimestamp: includeTimestampInFilename,
                                format: format
                             )
                        }
                    }
                    transcriptionManager.showSuccess = true
                } catch {
                    transcriptionManager.showError(message: "Export failed: \(error.localizedDescription)")
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
                        } else if transcriptionManager.isAudioFile(url) || transcriptionManager.isVideoFile(url) {
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

// MARK: - Subcomponents

struct DropZoneCard: View {
    let isDropTargeted: Bool
    let fileCount: Int
    let onSelectDirectory: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: fileCount > 0 ? "waveform" : "arrow.down.doc")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.accent)
            }

            VStack(spacing: 8) {
                Text(fileCount > 0 ? "\(fileCount) Files Selected" : "Drag Files Here")
                    .font(Theme.headerFont())
                    .foregroundColor(Theme.text)

                Text(fileCount > 0 ? "Ready to transcribe" : "Or select a directory to begin")
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.text.opacity(0.7))
            }

            if fileCount == 0 {
                Button("Select Directory") {
                    onSelectDirectory()
                }
                .buttonStyle(MCMButtonStyle(color: Theme.accent))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(isDropTargeted ? Theme.accent : Theme.border, lineWidth: isDropTargeted ? 2 : 1)
                        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
                )
                .shadow(color: Color.black.opacity(0.05), radius: Theme.shadowRadius, x: 0, y: 4)
        )
        .animation(.spring(), value: isDropTargeted)
        .animation(.spring(), value: fileCount)
    }
}

struct ControlPanelCard: View {
    @Binding var selectedModel: WhisperModel
    @Binding var customModelPath: String
    @Binding var selectedLanguage: Language
    @Binding var selectedExportFormats: Set<ExportFormat>
    @Binding var includeTimestampInFilename: Bool
    @Binding var alsoExportIndividualFiles: Bool

    let onBrowseModel: () -> Void
    let onExport: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Configuration")
                    .font(Theme.headerFont())
                    .foregroundColor(Theme.text)
                Spacer()
            }

            // Model & Language Row
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model").font(Theme.monoFont()).foregroundColor(Theme.text.opacity(0.6))
                    Picker("", selection: $selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Language").font(Theme.monoFont()).foregroundColor(Theme.text.opacity(0.6))
                    Picker("", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().opacity(0.5)

            // Export Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Formats").font(Theme.monoFont()).foregroundColor(Theme.text.opacity(0.6))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        Toggle(isOn: Binding(
                            get: { selectedExportFormats.contains(format) },
                            set: { isSelected in
                                if isSelected { selectedExportFormats.insert(format) }
                                else { selectedExportFormats.remove(format) }
                            }
                        )) {
                            Text(format.displayName)
                        }
                        .toggleStyle(MCMToggleStyle())
                    }
                }

                HStack(spacing: 16) {
                    Toggle("Time in Filename", isOn: $includeTimestampInFilename)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(Theme.monoFont())

                    if !selectedExportFormats.contains(.individualFiles) {
                         Toggle("Individual Files", isOn: $alsoExportIndividualFiles)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(Theme.monoFont())
                    }
                    Spacer()

                    if !selectedExportFormats.isEmpty {
                        Button("Export All") {
                            onExport()
                        }
                        .buttonStyle(MCMButtonStyle(color: Theme.secondaryAccent))
                        .scaleEffect(0.8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .mcmCard()
    }
}

struct ActionBar: View {
    let isProcessing: Bool
    let progress: Double
    let batchProgress: Double
    let statusMessage: String
    let completedCount: Int
    let totalCount: Int
    let hasFiles: Bool
    let hasResults: Bool
    let onStart: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if isProcessing {
                VStack(spacing: 8) {
                    // Batch Progress
                    HStack {
                         Text("Batch Progress: \(completedCount)/\(totalCount) files")
                             .font(Theme.monoFont().bold())
                             .foregroundColor(Theme.text)
                         Spacer()
                         Text("\(Int(batchProgress * 100))%")
                             .font(Theme.monoFont())
                             .foregroundColor(Theme.text.opacity(0.7))
                    }
                    ProgressView(value: batchProgress)
                         .progressViewStyle(.linear)
                         .tint(Theme.secondaryAccent) // Teal for batch

                    HStack {
                        Spacer()
                        Button(action: onCancel) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("Cancel")
                            }
                            .foregroundColor(.red)
                            .font(Theme.monoFont())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                    Divider().padding(.vertical, 4)

                    // File Progress
                    HStack {
                        Text(statusMessage)
                            .font(Theme.monoFont())
                            .foregroundColor(Theme.text.opacity(0.8))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(Theme.monoFont())
                            .foregroundColor(Theme.text.opacity(0.8))
                    }
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent) // Orange for current file
                }
                .mcmCard()
            } else if hasFiles {
                HStack(spacing: 16) {
                    Button(action: onStart) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Start Transcription")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MCMButtonStyle())

                    if hasResults {
                        Button(action: onReset) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(MCMButtonStyle(color: Theme.text.opacity(0.1)))
                        .frame(width: 50)
                    }
                }
            }
        }
    }
}

struct TranscriptionFeed: View {
    let audioFiles: [URL]
    let completedTranscriptions: [TranscriptionResult]
    let fileStatuses: [FileStatus]
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onPlayVideo: (URL) -> Void
    let transcriptionManager: TranscriptionManager // passed for isVideoFile check

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(audioFiles, id: \.self) { file in
                let status = fileStatuses.first(where: { $0.url == file })
                let isVideo = transcriptionManager.isVideoFile(file)
                let transcription = completedTranscriptions.first(where: { $0.sourcePath == file.path })

                FileCard(
                    file: file,
                    status: status,
                    transcription: transcription,
                    isVideo: isVideo,
                    isPlaying: audioPlayer.currentFile == file && audioPlayer.isPlaying,
                    livePreview: (status?.status == .processing) ? transcriptionManager.currentPreviewText : "",
                    elapsedTime: (status?.status == .processing) ? transcriptionManager.currentElapsed : 0,
                    remainingTime: (status?.status == .processing) ? transcriptionManager.currentRemaining : 0,
                    onPlay: {
                        if isVideo {
                             onPlayVideo(file)
                        } else {
                            if audioPlayer.isPlaying && audioPlayer.currentFile == file {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.play(file: file)
                            }
                        }
                    }
                )
            }
        }
    }
}

struct FileCard: View {
    let file: URL
    let status: FileStatus?
    let transcription: TranscriptionResult?
    let isVideo: Bool
    let isPlaying: Bool
    let livePreview: String // New parameter for real-time text
    let elapsedTime: TimeInterval
    let remainingTime: TimeInterval
    let onPlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon Column
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 20))
            }

            // Content Column
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.lastPathComponent)
                        .font(.headline)
                        .foregroundColor(Theme.text)
                        .lineLimit(1)

                    Spacer()

                    if let duration = transcription?.duration {
                        Text(formatDuration(duration))
                            .font(Theme.monoFont())
                            .foregroundColor(Theme.text.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(4)
                    }
                }

                if let transcription = transcription {
                    Text(transcription.preview)
                        .font(Theme.bodyFont())
                        .foregroundColor(Theme.text.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if status?.status == .processing {
                        VStack(alignment: .leading, spacing: 4) {
                            if !livePreview.isEmpty {
                                Text(livePreview)
                                    .font(Theme.monoFont())
                                    .foregroundColor(Theme.text.opacity(0.8))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            } else {
                                Text("Processing...")
                                    .font(Theme.monoFont())
                                    .foregroundColor(Theme.text.opacity(0.5))
                            }

                            // Progress Timing Stats
                             if elapsedTime > 0 {
                                 HStack(spacing: 8) {
                                     Label(TranscriptionManager.formatDuration(elapsedTime), systemImage: "stopwatch")
                                         .help("Elapsed Time")
                                     if remainingTime > 0 {
                                         Text("/")
                                             .foregroundColor(Theme.text.opacity(0.3))
                                         Label("-\(TranscriptionManager.formatDuration(remainingTime))", systemImage: "hourglass")
                                             .help("Remaining Time")
                                     }
                                 }
                                 .font(.system(size: 10, weight: .medium, design: .monospaced))
                                 .foregroundColor(Theme.secondaryAccent)
                                 .padding(.top, 2)
                             }
                        }
                    } else {
                        switch status?.status {
                        case .failed(let errorMessage):
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Failed")
                                    .font(Theme.monoFont().bold())
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(Theme.monoFont())
                                    .foregroundColor(.red.opacity(0.8))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        case .pending:
                            Text("Queued")
                                .font(Theme.monoFont())
                                .foregroundColor(Theme.text.opacity(0.5))
                        default:
                             Text("Pending")
                                .font(Theme.monoFont())
                                .foregroundColor(Theme.text.opacity(0.5))
                        }
                    }
                }
            }

            // Action Column
            Button(action: onPlay) {
                Image(systemName: isVideo ? "play.rectangle.fill" : (isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 32))
                    .foregroundColor(Theme.text.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(status?.status == .processing)
        }
        .padding(Theme.padding)
        .background(Theme.surface)
        .cornerRadius(Theme.cornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch status?.status {
        case .pending: return "clock"
        case .processing: return "hourglass"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .none: return "doc"
        }
    }

    private var statusColor: Color {
        switch status?.status {
        case .pending: return .secondary
        case .processing: return Theme.accent
        case .completed: return Theme.secondaryAccent // Teal for completion
        case .failed: return .red
        case .none: return .secondary
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        else { return String(format: "%d:%02d", minutes, secs) }
    }
}

#Preview {
    ContentView()
}
