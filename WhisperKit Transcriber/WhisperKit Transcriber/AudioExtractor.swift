//
//  AudioExtractor.swift
//  WhisperKitTranscriber
//
//  Created by User on 2026-01-08.
//

import Foundation
import AVFoundation

enum AudioExtractionError: LocalizedError {
    case exportSessionCreationFailed
    case extractionFailed(String?)
    case outputURLError

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .extractionFailed(let message):
            return "Audio extraction failed: \(message ?? "Unknown error")"
        case .outputURLError:
            return "Invalid output URL"
        }
    }
}

class AudioExtractor {
    static let shared = AudioExtractor()

    private init() {}

    /// Extracts audio from a video file and saves it as an m4a file in a temporary directory
    /// - Parameter videoURL: The URL of the video file
    /// - Returns: The URL of the extracted audio file
    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        // Create a unique output filename
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let outputFilename = UUID().uuidString + ".m4a"
        let outputURL = temporaryDirectory.appendingPathComponent(outputFilename)

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.exportSessionCreationFailed
        }

        exportSession.shouldOptimizeForNetworkUse = false

        // Use modern async export
        try await exportSession.export(to: outputURL, as: .m4a)

        return outputURL
    }

    /// Cleans up a temporary audio file
    /// - Parameter url: The URL of the file to remove
    func cleanup(url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to cleanup temporary audio file: \(error)")
        }
    }
}
