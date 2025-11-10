//
//  VideoPlayerView.swift
//  WhisperKitTranscriber
//
//  Video player with subtitle synchronization
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let videoURL: URL
    let transcription: TranscriptionResult?

    @Environment(\.dismiss) var dismiss
    @StateObject private var playerController = VideoPlayerController()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(videoURL.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            // Video player
            if let player = playerController.player {
                VideoPlayer(player: player)
                    .frame(minHeight: 400)
                    .overlay(alignment: .bottom) {
                        // Subtitle overlay
                        if playerController.showSubtitles,
                           let currentText = playerController.currentSubtitleText,
                           !currentText.isEmpty {
                            Text(currentText)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.75))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.bottom, 60)
                        }
                    }
                    .onAppear {
                        playerController.setupPlayer(videoURL: videoURL, transcription: transcription)
                    }
                    .onDisappear {
                        playerController.cleanup()
                    }
            } else {
                ProgressView("Loading video...")
                    .frame(height: 400)
            }

            // Controls
            VStack(spacing: 12) {
                // Playback controls
                HStack {
                    Button(action: playerController.togglePlayPause) {
                        Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }

                    // Time display
                    Text(formatTime(playerController.currentTime))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 50, alignment: .trailing)

                    // Seek slider
                    Slider(value: $playerController.currentTime, in: 0...playerController.duration) { editing in
                        if !editing {
                            playerController.seekToTime(playerController.currentTime)
                        }
                    }
                    .disabled(playerController.duration == 0)

                    Text(formatTime(playerController.duration))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 50)

                    // Speed control
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button(String(format: "%.2fx", speed)) {
                                playerController.setPlaybackSpeed(Float(speed))
                            }
                        }
                    } label: {
                        Text(String(format: "%.2fx", playerController.playbackRate))
                            .font(.caption)
                            .frame(minWidth: 50)
                    }
                }

                // Subtitle toggle
                Toggle("Show Subtitles", isOn: $playerController.showSubtitles)
                    .font(.caption)

                // Segment list (if available)
                if let transcription = transcription, !transcription.segments.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Segments (\(transcription.segments.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(transcription.segments.prefix(10)) { segment in
                                Button(action: {
                                    playerController.seekToTime(segment.startTime)
                                }) {
                                    HStack {
                                        Text(formatTime(segment.startTime))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(minWidth: 50, alignment: .trailing)

                                        Text(segment.text)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundColor(.primary)

                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                    .background(
                                        playerController.currentSegmentIndex == transcription.segments.firstIndex(where: { $0.id == segment.id })
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }

                            if transcription.segments.count > 10 {
                                Text("+ \(transcription.segments.count - 10) more segments")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }

        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Video Player Controller

class VideoPlayerController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var playbackRate: Float = 1.0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var showSubtitles = true
    @Published var currentSubtitleText: String?
    @Published var currentSegmentIndex: Int?

    private var timeObserver: Any?
    private var segments: [TranscriptionSegment] = []

    var duration: Double {
        guard let player = player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite else {
            return 0
        }
        return duration
    }

    func setupPlayer(videoURL: URL, transcription: TranscriptionResult?) {
        player = AVPlayer(url: videoURL)

        // Load segments
        if let transcription = transcription {
            segments = transcription.segments
        }

        // Observe time updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.updateCurrentSubtitle(time: time.seconds)
        }

        // Observe playback status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }

        // Set initial playback rate
        player?.rate = playbackRate
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    func seekToTime(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackRate = speed
        if isPlaying {
            player?.rate = speed
        }
    }

    private func updateCurrentSubtitle(time: Double) {
        guard showSubtitles else {
            currentSubtitleText = nil
            currentSegmentIndex = nil
            return
        }

        // Find subtitle segment for current time
        if let index = segments.firstIndex(where: { time >= $0.startTime && time <= $0.endTime }) {
            currentSubtitleText = segments[index].text
            currentSegmentIndex = index
        } else {
            currentSubtitleText = nil
            currentSegmentIndex = nil
        }
    }
}
