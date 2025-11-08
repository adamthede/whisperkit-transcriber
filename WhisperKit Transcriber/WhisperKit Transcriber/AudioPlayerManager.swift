//
//  AudioPlayerManager.swift
//  WhisperKitTranscriber
//
//  Manages audio playback for previewing files
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

@MainActor
class AudioPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentFile: URL?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    override init() {
        super.init()
    }

    deinit {
        // Clean up synchronously in deinit
        player?.pause()
        player?.seek(to: .zero)
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
        player = nil
    }

    func play(file: URL) {
        // Stop current playback if different file
        if currentFile != file {
            stop()
        }

        // Create new player if needed
        if player == nil {
            let newPlayer = AVPlayer(url: file)
            player = newPlayer

            // Observe time updates
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    self?.currentTime = CMTimeGetSeconds(time)
                }
            }

            // Observe when playback ends
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem
            )
        }

        currentFile = file

        // Get duration using async load
        Task { @MainActor in
            if let asset = player?.currentItem?.asset {
                do {
                    let duration = try await asset.load(.duration)
                    self.duration = CMTimeGetSeconds(duration)
                } catch {
                    print("Failed to load duration: \(error)")
                }
            }
        }

        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentFile = nil
        currentTime = 0
        duration = 0

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        NotificationCenter.default.removeObserver(self)
        player = nil
    }

    func stopAsync() async {
        stop()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }

    @objc private func playerDidFinishPlaying() {
        Task { @MainActor in
            isPlaying = false
            currentTime = 0
        }
    }
}

