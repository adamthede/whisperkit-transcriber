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
