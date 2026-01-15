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

        // Load tracks (Async in macOS 12+)
        let tracks = try await asset.load(.tracks)
        let audioTracks = tracks.filter { $0.mediaType == .audio }

        guard !audioTracks.isEmpty else {
            throw AudioExtractionError.extractionFailed("No audio tracks found in video file")
        }

        // Debug Logging
        for (index, track) in audioTracks.enumerated() {
            print("🔊 Track \(index): MediaType=\(track.mediaType.rawValue)")
        }

        // Create a unique output filename
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let outputFilename = UUID().uuidString + ".m4a"
        let outputURL = temporaryDirectory.appendingPathComponent(outputFilename)

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Robust Extraction: Create an Audio-Only Composition
        // This isolates the export from potentially corrupt video tracks (common in NVR files)
        // which often cause "Invalid sample cursor" errors.
        let composition = AVMutableComposition()

        // Insert audio tracks
        for track in audioTracks {
            guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }

            do {
                let timeRange = try await track.load(.timeRange)
                try compositionTrack.insertTimeRange(timeRange, of: track, at: .zero)
            } catch {
                print("⚠️ Failed to insert track: \(error)")
            }
        }

        // Create export session with the COMPOSITION, not the raw asset
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.exportSessionCreationFailed
        }

        exportSession.shouldOptimizeForNetworkUse = false

        // Use modern async export
        do {
            if #available(macOS 12.0, *) {
                try await exportSession.export(to: outputURL, as: .m4a)
            } else {
                // Fallback for older macOS
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                await exportSession.export()
                if let error = exportSession.error { throw error }
            }
        } catch {
             print("❌ Audio Composition Export failed: \(error.localizedDescription)")
             print("⚠️ Attempting manual transcoding fallback (AVAssetReader/Writer)...")

             // Fallback: Manual Transcoding
             // This is the most robust method for NVR files with corrupt sample tables.
             // We read raw samples (LPCM) and re-encode them.
             do {
                 try await manualEncodeAudio(from: asset, to: outputURL)
                 return outputURL
             } catch let manualError {
                 print("❌ Manual transcoding failed: \(manualError.localizedDescription)")

                 // Fallback Level 3: FFmpeg (The "Nuclear" Option)
                 // If the user has FFmpeg installed, it is extremely robust against corrupt headers.
                 if let ffmpegPath = findFFmpeg() {
                     print("⚠️ Attempting FFmpeg fallback...")
                     try await extractWithFFmpeg(ffmpegPath: ffmpegPath, videoURL: videoURL, outputURL: outputURL)
                     return outputURL
                 } else {
                     throw AudioExtractionError.extractionFailed("All extraction methods failed. Native error: \(manualError.localizedDescription)")
                 }
             }
        }

        return outputURL
    }

    // MARK: - FFmpeg Support

    private func findFFmpeg() -> String? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func extractWithFFmpeg(ffmpegPath: String, videoURL: URL, outputURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        // -i [input] -vn (no video) -c:a aac (recnode to AAC) -b:a 64k (bitrate) -y (overwrite) [output]
        process.arguments = [
            "-i", videoURL.path,
            "-vn",
            "-c:a", "aac",
            "-b:a", "64k",
            "-y",
            outputURL.path
        ]

        // Capture stderr for debugging
        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown stderr"
            throw AudioExtractionError.extractionFailed("FFmpeg failed: \(output)")
        }
    }

    /// Manually reads audio samples and re-encodes them to AAC.
    /// This bypasses high-level export session validation checks that fail on NVR files.
    private func manualEncodeAudio(from asset: AVAsset, to outputURL: URL) async throws {
        // 1. Setup Reader
        let reader = try AVAssetReader(asset: asset)
        let audioTracks = try await asset.load(.tracks).filter { $0.mediaType == .audio }
        guard let track = audioTracks.first else { throw AudioExtractionError.extractionFailed("No audio track") }

        // Decompress to Linear PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        } else {
            throw AudioExtractionError.extractionFailed("Cannot add reader output")
        }

        // 2. Setup Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        // Compress to AAC
        let compressionSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, // Mono for transcription is usually fine/better
            AVEncoderBitRateKey: 96000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: compressionSettings)
        writerInput.expectsMediaDataInRealTime = false

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        } else {
            throw AudioExtractionError.extractionFailed("Cannot add writer input")
        }

        // 3. Start Processing
        guard reader.startReading() else {
            throw AudioExtractionError.extractionFailed("Reader failed to start: \(reader.error?.localizedDescription ?? "Unknown")")
        }
        guard writer.startWriting() else {
             throw AudioExtractionError.extractionFailed("Writer failed to start: \(writer.error?.localizedDescription ?? "Unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        // 4. Loop
        let processingQueue = DispatchQueue(label: "audio.processing")

        // Wrap non-Sendable AVFoundation objects in a container to satisfy strict concurrency checks.
        // We ensure thread safety by only accessing them within the serial processingQueue (as intended by AVFoundation).
        struct EncodingContext: @unchecked Sendable {
            let reader: AVAssetReader
            let readerOutput: AVAssetReaderTrackOutput
            let writer: AVAssetWriter
            let writerInput: AVAssetWriterInput
        }
        let context = EncodingContext(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)

        return try await withCheckedThrowingContinuation { continuation in
            context.writerInput.requestMediaDataWhenReady(on: processingQueue) {
                let input = context.writerInput
                let output = context.readerOutput

                while input.isReadyForMoreMediaData {
                    if let buffer = output.copyNextSampleBuffer() {
                        input.append(buffer)
                    } else {
                        // EOF or Error
                        input.markAsFinished()
                        if context.reader.status == .failed {
                            continuation.resume(throwing: context.reader.error ?? AudioExtractionError.extractionFailed("Reader failed mid-stream"))
                        } else {
                            // Success
                            context.writer.finishWriting {
                                if context.writer.status == .failed {
                                    continuation.resume(throwing: context.writer.error ?? AudioExtractionError.extractionFailed("Writer failed at finish"))
                                } else {
                                    continuation.resume()
                                }
                            }
                        }
                        return
                    }
                }
            }
        }
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
