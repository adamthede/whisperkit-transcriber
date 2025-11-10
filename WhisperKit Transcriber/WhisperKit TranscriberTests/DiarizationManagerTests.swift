//
//  DiarizationManagerTests.swift
//  WhisperKitTranscriberTests
//
//  Unit tests for DiarizationManager
//

import XCTest
@testable import WhisperKit_Transcriber

class DiarizationManagerTests: XCTestCase {

    var diarizationManager: DiarizationManager!

    override func setUpWithError() throws {
        diarizationManager = DiarizationManager.shared
    }

    override func tearDownWithError() throws {
        diarizationManager = nil
    }

    // MARK: - Merge Tests

    func testMergeDiarizationWithTranscription() throws {
        // Given: Transcription segments
        let transcriptionSegments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Hello there"),
            TranscriptionSegment(startTime: 5.0, endTime: 10.0, text: "How are you"),
            TranscriptionSegment(startTime: 10.0, endTime: 15.0, text: "I'm doing well")
        ]

        // Given: Diarization segments
        let diarizationSegments = [
            SpeakerSegment(startTime: 0.0, endTime: 7.0, text: "", speakerID: "SPEAKER_00"),
            SpeakerSegment(startTime: 7.0, endTime: 15.0, text: "", speakerID: "SPEAKER_01")
        ]

        // When: Merging
        let merged = diarizationManager.mergeDiarizationWithTranscription(
            diarization: diarizationSegments,
            transcriptionSegments: transcriptionSegments
        )

        // Then: Verify correct speaker assignment
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].speaker, "SPEAKER_00", "First segment should be SPEAKER_00")
        XCTAssertEqual(merged[1].speaker, "SPEAKER_00", "Second segment should be SPEAKER_00 (starts at 5s)")
        XCTAssertEqual(merged[2].speaker, "SPEAKER_01", "Third segment should be SPEAKER_01 (starts at 10s)")
    }

    func testMergeDiarizationWithNoOverlap() throws {
        // Given: Transcription segments that don't overlap with diarization
        let transcriptionSegments = [
            TranscriptionSegment(startTime: 20.0, endTime: 25.0, text: "Late segment")
        ]

        // Given: Diarization segments ending before transcription
        let diarizationSegments = [
            SpeakerSegment(startTime: 0.0, endTime: 10.0, text: "", speakerID: "SPEAKER_00")
        ]

        // When: Merging
        let merged = diarizationManager.mergeDiarizationWithTranscription(
            diarization: diarizationSegments,
            transcriptionSegments: transcriptionSegments
        )

        // Then: Segment should have no speaker assigned
        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].speaker, "Segment should have no speaker when no overlap")
    }

    func testMergeDiarizationWithEmptyDiarization() throws {
        // Given: Transcription segments
        let transcriptionSegments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Hello")
        ]

        // Given: Empty diarization
        let diarizationSegments: [SpeakerSegment] = []

        // When: Merging
        let merged = diarizationManager.mergeDiarizationWithTranscription(
            diarization: diarizationSegments,
            transcriptionSegments: transcriptionSegments
        )

        // Then: All segments should have no speaker
        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].speaker)
    }

    // MARK: - Speaker Segment Tests

    func testSpeakerSegmentProperties() throws {
        // Given: A speaker segment
        let segment = SpeakerSegment(
            startTime: 1.5,
            endTime: 5.5,
            text: "Test text",
            speakerID: "SPEAKER_00"
        )

        // Then: Properties should be correct
        XCTAssertEqual(segment.startTime, 1.5)
        XCTAssertEqual(segment.endTime, 5.5)
        XCTAssertEqual(segment.text, "Test text")
        XCTAssertEqual(segment.speakerID, "SPEAKER_00")
    }

    // MARK: - Error Tests

    func testDiarizationErrorDescriptions() throws {
        // Test error descriptions
        let invalidURLError = DiarizationError.invalidServerURL
        XCTAssertNotNil(invalidURLError.errorDescription)
        XCTAssertTrue(invalidURLError.errorDescription!.contains("Invalid diarization server URL"))

        let serverError = DiarizationError.serverError("Connection failed")
        XCTAssertNotNil(serverError.errorDescription)
        XCTAssertTrue(serverError.errorDescription!.contains("Connection failed"))

        let invalidResponse = DiarizationError.invalidResponse
        XCTAssertNotNil(invalidResponse.errorDescription)
        XCTAssertTrue(invalidResponse.errorDescription!.contains("Invalid response"))

        let fileReadError = DiarizationError.fileReadError
        XCTAssertNotNil(fileReadError.errorDescription)
        XCTAssertTrue(fileReadError.errorDescription!.contains("Failed to read audio file"))

        let mergeFailed = DiarizationError.mergeFailed
        XCTAssertNotNil(mergeFailed.errorDescription)
        XCTAssertTrue(mergeFailed.errorDescription!.contains("merge"))
    }

    // MARK: - Server URL Tests

    func testUpdateServerURL() throws {
        // Given: New server URL
        let newURL = "http://example.com:8080/diarize"

        // When: Updating server URL
        diarizationManager.updateServerURL(newURL)

        // Then: URL should be stored in UserDefaults
        let storedURL = UserDefaults.standard.string(forKey: "diarizationServerURL")
        XCTAssertEqual(storedURL, newURL)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "diarizationServerURL")
    }
}
