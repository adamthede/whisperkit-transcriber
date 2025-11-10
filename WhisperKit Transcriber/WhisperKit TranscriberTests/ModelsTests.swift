//
//  ModelsTests.swift
//  WhisperKitTranscriberTests
//
//  Unit tests for Models with speaker support
//

import XCTest
@testable import WhisperKit_Transcriber

class ModelsTests: XCTestCase {

    // MARK: - TranscriptionSegment Tests

    func testTranscriptionSegmentInit() throws {
        // Given: Create a transcription segment
        let segment = TranscriptionSegment(
            startTime: 1.5,
            endTime: 5.5,
            text: "Hello world",
            speaker: "SPEAKER_00",
            speakerName: "John"
        )

        // Then: All properties should be set correctly
        XCTAssertEqual(segment.startTime, 1.5)
        XCTAssertEqual(segment.endTime, 5.5)
        XCTAssertEqual(segment.text, "Hello world")
        XCTAssertEqual(segment.speaker, "SPEAKER_00")
        XCTAssertEqual(segment.speakerName, "John")
    }

    func testTranscriptionSegmentWithoutSpeaker() throws {
        // Given: Create a segment without speaker info
        let segment = TranscriptionSegment(
            startTime: 0.0,
            endTime: 2.0,
            text: "No speaker"
        )

        // Then: Speaker fields should be nil
        XCTAssertNil(segment.speaker)
        XCTAssertNil(segment.speakerName)
    }

    // MARK: - TranscriptionResult Tests

    func testTranscriptionResultWithSpeakers() throws {
        // Given: Create transcription with speaker segments
        let segments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Hello", speaker: "SPEAKER_00"),
            TranscriptionSegment(startTime: 5.0, endTime: 10.0, text: "Hi", speaker: "SPEAKER_01"),
            TranscriptionSegment(startTime: 10.0, endTime: 15.0, text: "How are you", speaker: "SPEAKER_00")
        ]

        let speakerLabels = [
            "SPEAKER_00": "Alice",
            "SPEAKER_01": "Bob"
        ]

        let result = TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Hello Hi How are you",
            duration: 15,
            createdAt: Date(),
            segments: segments,
            speakerLabels: speakerLabels
        )

        // Then: hasSpeakers should be true
        XCTAssertTrue(result.hasSpeakers)

        // Then: uniqueSpeakers should contain both speakers
        XCTAssertEqual(result.uniqueSpeakers.count, 2)
        XCTAssertTrue(result.uniqueSpeakers.contains("SPEAKER_00"))
        XCTAssertTrue(result.uniqueSpeakers.contains("SPEAKER_01"))

        // Then: Speaker labels should be stored
        XCTAssertEqual(result.speakerLabels["SPEAKER_00"], "Alice")
        XCTAssertEqual(result.speakerLabels["SPEAKER_01"], "Bob")
    }

    func testTranscriptionResultWithoutSpeakers() throws {
        // Given: Create transcription without speakers
        let result = TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Simple transcription",
            duration: 10,
            createdAt: Date()
        )

        // Then: hasSpeakers should be false
        XCTAssertFalse(result.hasSpeakers)

        // Then: uniqueSpeakers should be empty
        XCTAssertTrue(result.uniqueSpeakers.isEmpty)
    }

    func testTranscriptionResultSegmentsWithoutSpeakerIDs() throws {
        // Given: Segments without speaker IDs
        let segments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Hello"),
            TranscriptionSegment(startTime: 5.0, endTime: 10.0, text: "World")
        ]

        let result = TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Hello World",
            duration: 10,
            createdAt: Date(),
            segments: segments
        )

        // Then: hasSpeakers should be false (segments have no speaker IDs)
        XCTAssertFalse(result.hasSpeakers)
    }

    func testUniqueSpeakersSorted() throws {
        // Given: Multiple segments with speakers in random order
        let segments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Text", speaker: "SPEAKER_02"),
            TranscriptionSegment(startTime: 5.0, endTime: 10.0, text: "Text", speaker: "SPEAKER_00"),
            TranscriptionSegment(startTime: 10.0, endTime: 15.0, text: "Text", speaker: "SPEAKER_01"),
            TranscriptionSegment(startTime: 15.0, endTime: 20.0, text: "Text", speaker: "SPEAKER_00")
        ]

        let result = TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Text",
            duration: 20,
            createdAt: Date(),
            segments: segments
        )

        // Then: uniqueSpeakers should be sorted and unique
        XCTAssertEqual(result.uniqueSpeakers, ["SPEAKER_00", "SPEAKER_01", "SPEAKER_02"])
    }

    func testSpeakerLabelManagement() throws {
        // Given: Transcription with speakers
        let segments = [
            TranscriptionSegment(startTime: 0.0, endTime: 5.0, text: "Hello", speaker: "SPEAKER_00")
        ]

        let result = TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Hello",
            duration: 5,
            createdAt: Date(),
            segments: segments
        )

        // When: Adding speaker labels
        result.speakerLabels["SPEAKER_00"] = "Alice"
        result.speakerLabels["SPEAKER_01"] = "Bob"

        // Then: Labels should be stored correctly
        XCTAssertEqual(result.speakerLabels.count, 2)
        XCTAssertEqual(result.speakerLabels["SPEAKER_00"], "Alice")
        XCTAssertEqual(result.speakerLabels["SPEAKER_01"], "Bob")

        // When: Updating a label
        result.speakerLabels["SPEAKER_00"] = "Alicia"

        // Then: Label should be updated
        XCTAssertEqual(result.speakerLabels["SPEAKER_00"], "Alicia")
    }

    // MARK: - Hashable Tests

    func testTranscriptionResultHashable() throws {
        // Given: Two transcription results with same ID
        let id = UUID()
        let result1 = TranscriptionResult(
            id: id,
            sourcePath: "/path/1",
            fileName: "file1.mp3",
            text: "Text 1",
            duration: 10,
            createdAt: Date()
        )

        let result2 = TranscriptionResult(
            id: id,
            sourcePath: "/path/2",
            fileName: "file2.mp3",
            text: "Text 2",
            duration: 20,
            createdAt: Date()
        )

        // Then: They should be equal (based on ID)
        XCTAssertEqual(result1, result2)

        // Then: They should have the same hash
        XCTAssertEqual(result1.hashValue, result2.hashValue)
    }

    func testTranscriptionResultNotEqual() throws {
        // Given: Two transcription results with different IDs
        let result1 = TranscriptionResult(
            sourcePath: "/path/1",
            fileName: "file1.mp3",
            text: "Text 1",
            duration: 10,
            createdAt: Date()
        )

        let result2 = TranscriptionResult(
            sourcePath: "/path/1",
            fileName: "file1.mp3",
            text: "Text 1",
            duration: 10,
            createdAt: Date()
        )

        // Then: They should not be equal (different IDs)
        XCTAssertNotEqual(result1, result2)
    }
}
