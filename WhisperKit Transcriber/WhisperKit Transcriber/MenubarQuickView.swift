//
//  MenubarQuickView.swift
//  WhisperKit Transcriber
//
//  Quick transcription interface for menubar
//

import SwiftUI
import UniformTypeIdentifiers

struct MenubarQuickView: View {
    @StateObject private var transcriptionManager = TranscriptionManager()
    @State private var selectedFile: URL?
    @State private var isProcessing = false
    @State private var showFilePicker = false
    @State private var showSettings = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Quick Transcribe")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            // File selection
            VStack(spacing: 12) {
                if let file = selectedFile {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.blue)
                        Text(file.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(action: {
                            selectedFile = nil
                            transcriptionManager.completedTranscriptions = []
                            errorMessage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Button(action: {
                        showFilePicker = true
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Choose Audio File")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            // Language selection (compact)
            if selectedFile != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $transcriptionManager.selectedLanguage) {
                        ForEach(Language.allCases.prefix(10)) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
            }

            // Transcribe button
            if selectedFile != nil && !isProcessing && transcriptionManager.completedTranscriptions.isEmpty {
                Button(action: {
                    Task {
                        await transcribeFile()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Transcribe")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }

            // Progress indicator
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            // Error message
            if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Result display
            if let result = transcriptionManager.completedTranscriptions.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(result.displayText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Copy button
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(result.displayText, forType: .string)
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy to Clipboard")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            Spacer()

            // Open main window button
            Divider()
            Button(action: {
                openMainWindow()
            }) {
                HStack {
                    Image(systemName: "square.split.2x2")
                    Text("Open Main Window")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 400, height: 500)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFile = urls.first
                errorMessage = nil
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showSettings) {
            MenubarSettingsView()
        }
    }

    private func transcribeFile() async {
        guard let file = selectedFile else { return }

        isProcessing = true
        errorMessage = nil

        // Add file to transcription manager
        await MainActor.run {
            transcriptionManager.audioFiles = [file]
            transcriptionManager.fileStatuses = [
                FileStatus(id: UUID(), url: file, status: .pending)
            ]
        }

        // Transcribe
        let modelPath = transcriptionManager.getModelPath()

        do {
            await MainActor.run {
                transcriptionManager.fileStatuses[0].status = .processing
            }

            let result = try await transcriptionManager.transcribeFile(file, modelPath: modelPath)

            await MainActor.run {
                transcriptionManager.completedTranscriptions = [result]
                transcriptionManager.fileStatuses[0].status = .completed
                transcriptionManager.fileStatuses[0].transcription = result
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                transcriptionManager.fileStatuses[0].status = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func openMainWindow() {
        // Try to find existing window
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible == false || $0.title.contains("WhisperKit") }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // If no window found, just activate the app
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenubarSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("menubarMode") var menubarMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menubar Settings")
                .font(.title2)
                .fontWeight(.bold)

            Toggle("Menubar Mode", isOn: Binding(
                get: { menubarMode },
                set: { newValue in
                    menubarMode = newValue
                    // Notify menubar manager
                    NotificationCenter.default.post(name: .toggleMenubarMode, object: newValue)
                }
            ))
            .help("Hide dock icon and show only in menubar")

            Text("When enabled, the app will only appear in the menubar and won't show in the dock.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

#Preview {
    MenubarQuickView()
}
