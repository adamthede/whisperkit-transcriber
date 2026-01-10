//
//  VideoPlayerView.swift
//  WhisperKitTranscriber
//
//  Created by User on 2026-01-08.
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let videoURL: URL
    let transcription: TranscriptionResult?
    @Environment(\.presentationMode) var presentationMode

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showSubtitles = true
    @State private var playbackRate: Float = 1.0
    @State private var currentSubtitleSegment: TranscriptionSegment?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(videoURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            // Video Player
            ZStack {
                Color.black

                if let player = player {
                    VideoPlayer(player: player)
                }

                // Subtitles Overlay
                if showSubtitles, let segment = currentSubtitleSegment {
                    VStack {
                        Spacer()
                        Text(segment.text)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.7))
                            )
                            .padding(.bottom, 40)
                            .transition(.opacity)
                    }
                }
            }

            // Controls
            VStack(spacing: 12) {
                // Scrubber
                HStack(spacing: 12) {
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .monospacedDigit()

                    Slider(value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            seek(to: newValue)
                        }
                    ), in: 0...max(duration, 0.1))

                    Text(formatTime(duration))
                        .font(.caption)
                        .monospacedDigit()
                }

                HStack {
                    // Speed Control
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button("\(String(format: "%.2fx", speed))") {
                                setPlaybackRate(Float(speed))
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.1fx", playbackRate))")
                            .font(.caption)
                            .padding(6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }

                    Spacer()

                    // Play/Pause
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Subtitles Toggle
                    Button(action: { showSubtitles.toggle() }) {
                        Image(systemName: showSubtitles ? "captions.bubble.fill" : "captions.bubble")
                            .font(.title2)
                            .foregroundColor(showSubtitles ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        isPlaying = true

        // Observe duration
        Task {
            do {
                if let duration = try await player?.currentItem?.asset.load(.duration) {
                    await MainActor.run {
                        self.duration = CMTimeGetSeconds(duration)
                    }
                }
            } catch {
                print("Error loading duration: \(error)")
            }
        }

        // Time observer for progress and subtitles
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isPlaying || player?.rate != 0 else { return } // Avoid jitter during seeking
            currentTime = time.seconds
            updateSubtitle(for: time.seconds)
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if player.rate != 0 {
            player.pause()
            isPlaying = false
        } else {
            // If ended, restart
            if currentTime >= duration {
                seek(to: 0)
            }
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateSubtitle(for: time)
    }

    private func setPlaybackRate(_ rate: Float) {
        playbackRate = Float(rate)
        if isPlaying {
            player?.rate = rate
        }
    }

    private func updateSubtitle(for time: Double) {
        guard let transcription = transcription, !transcription.segments.isEmpty else { return }

        // Binary search for performance O(log N)
        // We want to find a segment where start <= time <= end
        // Segments are sorted by start time

        let segments = transcription.segments
        var low = 0
        var high = segments.count - 1
        var foundSegment: TranscriptionSegment? = nil

        while low <= high {
            let mid = (low + high) / 2
            let segment = segments[mid]

            if time < segment.start {
                high = mid - 1
            } else if time > segment.end {
                low = mid + 1
            } else {
                // time is between start and end
                foundSegment = segment
                break
            }
        }

        if let segment = foundSegment {
            if currentSubtitleSegment?.id != segment.id {
                withAnimation(.easeInOut(duration: 0.1)) {
                    currentSubtitleSegment = segment
                }
            }
        } else {
            if currentSubtitleSegment != nil {
                withAnimation(.easeInOut(duration: 0.1)) {
                    currentSubtitleSegment = nil
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }

        let seconds = Int(seconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
