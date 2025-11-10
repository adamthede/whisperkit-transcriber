//
//  DiarizationManager.swift
//  WhisperKitTranscriber
//
//  Manages speaker diarization
//

import Foundation

class DiarizationManager {
    static let shared = DiarizationManager()

    private let diarizationServerURL: String

    private init() {
        // Load from UserDefaults or use default
        diarizationServerURL = UserDefaults.standard.string(forKey: "diarizationServerURL")
            ?? "http://localhost:50061/diarize"
    }

    func diarize(audioFile: URL) async throws -> [SpeakerSegment] {
        // Check if WhisperKit CLI supports diarization
        if await whisperkitSupportsDiarization() {
            return try await diarizeViaWhisperKit(audioFile: audioFile)
        } else {
            return try await diarizeViaServer(audioFile: audioFile)
        }
    }

    private func whisperkitSupportsDiarization() async -> Bool {
        // Check if whisperkit-cli supports --diarize flag
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", "whisperkit-cli transcribe --help 2>&1 | grep -i 'diar\\|speaker'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                // If we found diarization-related options, it's supported
                print("✅ WhisperKit CLI supports diarization")
                return true
            }
        } catch {
            print("⚠️ Could not check WhisperKit CLI diarization support: \(error)")
        }

        print("ℹ️ WhisperKit CLI does not support diarization, will use server if configured")
        return false
    }

    private func diarizeViaWhisperKit(audioFile: URL) async throws -> [SpeakerSegment] {
        // Use WhisperKit CLI diarization if available
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Properly quote the audio path
        let quotedPath = "'\(audioFile.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        let commandString = "whisperkit-cli transcribe --audio-path \(quotedPath) --diarize --output-format json"
        process.arguments = ["-l", "-c", commandString]

        // Set environment to ensure PATH includes Homebrew
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DiarizationError.serverError("WhisperKit diarization failed: \(output)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiarizationError.invalidResponse
        }

        return try parseWhisperKitDiarization(json: json)
    }

    private func diarizeViaServer(audioFile: URL) async throws -> [SpeakerSegment] {
        // Use diarization server API
        guard let url = URL(string: diarizationServerURL) else {
            throw DiarizationError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600 // 10 minutes timeout for large files

        // Create multipart form data with audio file
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audioFile.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)

        guard let audioData = try? Data(contentsOf: audioFile) else {
            throw DiarizationError.fileReadError
        }
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiarizationError.serverError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DiarizationError.serverError("Server returned status \(httpResponse.statusCode): \(errorMsg)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiarizationError.invalidResponse
        }

        return try parseServerDiarization(json: json)
    }

    private func parseWhisperKitDiarization(json: [String: Any]) throws -> [SpeakerSegment] {
        // Parse WhisperKit JSON output with speaker segments
        // Format depends on WhisperKit output structure
        guard let segments = json["segments"] as? [[String: Any]] else {
            throw DiarizationError.invalidResponse
        }

        var speakerSegments: [SpeakerSegment] = []

        for segment in segments {
            guard let start = segment["start"] as? Double,
                  let end = segment["end"] as? Double,
                  let text = segment["text"] as? String else {
                continue
            }

            // Speaker ID might be optional
            let speaker = segment["speaker"] as? String

            speakerSegments.append(SpeakerSegment(
                startTime: start,
                endTime: end,
                text: text,
                speakerID: speaker ?? "SPEAKER_00"
            ))
        }

        return speakerSegments
    }

    private func parseServerDiarization(json: [String: Any]) throws -> [SpeakerSegment] {
        // Parse diarization server response
        // Expected format based on typical diarization server output
        guard let segments = json["segments"] as? [[String: Any]] else {
            throw DiarizationError.invalidResponse
        }

        var speakerSegments: [SpeakerSegment] = []

        for segment in segments {
            guard let start = segment["start"] as? Double,
                  let end = segment["end"] as? Double,
                  let speaker = segment["speaker"] as? String else {
                continue
            }

            // Server may not include text, just timestamps
            let text = segment["text"] as? String ?? ""

            speakerSegments.append(SpeakerSegment(
                startTime: start,
                endTime: end,
                text: text,
                speakerID: speaker
            ))
        }

        return speakerSegments
    }

    func mergeDiarizationWithTranscription(
        diarization: [SpeakerSegment],
        transcriptionSegments: [TranscriptionSegment]
    ) -> [TranscriptionSegment] {
        // Merge speaker segments with transcription text
        // Assign speaker to transcription segments based on time overlap

        var mergedSegments: [TranscriptionSegment] = []

        for transSegment in transcriptionSegments {
            // Find overlapping diarization segment
            // A segment overlaps if the transcription start time falls within the diarization segment
            let overlappingDiar = diarization.first { diar in
                transSegment.startTime >= diar.startTime &&
                transSegment.startTime < diar.endTime
            }

            let mergedSegment = TranscriptionSegment(
                id: transSegment.id,
                startTime: transSegment.startTime,
                endTime: transSegment.endTime,
                text: transSegment.text,
                speaker: overlappingDiar?.speakerID,
                speakerName: nil
            )

            mergedSegments.append(mergedSegment)
        }

        return mergedSegments
    }

    func updateServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "diarizationServerURL")
    }
}

// MARK: - Supporting Types

struct SpeakerSegment {
    let startTime: Double
    let endTime: Double
    let text: String
    let speakerID: String
}

enum DiarizationError: LocalizedError {
    case invalidServerURL
    case serverError(String)
    case invalidResponse
    case fileReadError
    case mergeFailed

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid diarization server URL"
        case .serverError(let message):
            return "Diarization server error: \(message)"
        case .invalidResponse:
            return "Invalid response from diarization server"
        case .fileReadError:
            return "Failed to read audio file"
        case .mergeFailed:
            return "Failed to merge diarization with transcription"
        }
    }
}
