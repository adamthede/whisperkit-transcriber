//
//  SpeakerAssignmentView.swift
//  WhisperKitTranscriber
//
//  UI for assigning names to speakers
//

import SwiftUI

struct SpeakerAssignmentView: View {
    @ObservedObject var transcription: TranscriptionResult
    @State private var editingSpeaker: String?
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speaker Labels")
                .font(.headline)

            if transcription.hasSpeakers {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(transcription.uniqueSpeakers, id: \.self) { speakerID in
                        HStack {
                            Circle()
                                .fill(colorForSpeaker(speakerID))
                                .frame(width: 16, height: 16)

                            Text(speakerID)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)

                            if editingSpeaker == speakerID {
                                TextField("Name", text: $newName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)

                                Button("Save") {
                                    transcription.speakerLabels[speakerID] = newName.isEmpty ? nil : newName
                                    editingSpeaker = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Cancel") {
                                    editingSpeaker = nil
                                    newName = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                if let name = transcription.speakerLabels[speakerID] {
                                    Text(name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .frame(width: 150, alignment: .leading)
                                } else {
                                    Text("(No name)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 150, alignment: .leading)
                                }

                                Button(transcription.speakerLabels[speakerID] != nil ? "Edit" : "Set Name") {
                                    editingSpeaker = speakerID
                                    newName = transcription.speakerLabels[speakerID] ?? ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("No speaker diarization available for this transcription")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func colorForSpeaker(_ speakerID: String) -> Color {
        // Assign consistent colors to speakers
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink, .cyan, .mint, .indigo, .teal]
        let index = abs(speakerID.hashValue) % colors.count
        return colors[index]
    }
}

#Preview {
    SpeakerAssignmentView(
        transcription: TranscriptionResult(
            sourcePath: "/path/to/audio.mp3",
            fileName: "audio.mp3",
            text: "Sample transcription",
            duration: 120,
            createdAt: Date(),
            segments: [
                TranscriptionSegment(startTime: 0, endTime: 5, text: "Hello", speaker: "SPEAKER_00"),
                TranscriptionSegment(startTime: 5, endTime: 10, text: "Hi there", speaker: "SPEAKER_01")
            ]
        )
    )
    .frame(width: 500)
}
