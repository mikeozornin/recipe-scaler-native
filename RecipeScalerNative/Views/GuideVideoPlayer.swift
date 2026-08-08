//
//  GuideVideoPlayer.swift
//  RecipeScalerNative
//
//  Spec 040 — muted, auto-looping video block for the guide screen. Looks up
//  the mp4 in the main bundle by name (without extension). If the file is
//  missing, renders a `GuideAssetPlaceholder` so the screen still ships.
//

import AVKit
import SwiftUI

struct GuideVideoPlayer: View {
    let resourceName: String

    @State private var player: AVPlayerLoopController?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player.avPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(Text(verbatim: resourceName))
                    .accessibilityAddTraits(.startsMediaSession)
            } else {
                GuideAssetPlaceholder(name: resourceName)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
        .onAppear { configurePlayerIfNeeded() }
        .onDisappear { tearDownPlayer() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                player?.avPlayer.play()
            case .inactive, .background:
                player?.avPlayer.pause()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Player lifecycle

    /// Spec 040 — muted (silent guide clips), loops to the start on
    /// AVPlayerItemDidPlayToEndTime. The observer is owned by
    /// `AVPlayerLoopController` (ObservableObject) so its `deinit` reliably
    /// removes the notification observer even if `onDisappear` is skipped.
    private func configurePlayerIfNeeded() {
        guard player == nil else { return }
        guard let url = GuideAssetResolver.videoURL(forResourceName: resourceName) else {
            player = nil
            return
        }
        player = AVPlayerLoopController(url: url)
        player?.avPlayer.play()
    }

    private func tearDownPlayer() {
        player?.detach()
        player = nil
    }

    // MARK: - Layout

    @State private var availableWidth: CGFloat = 0

    private var videoHeight: CGFloat {
        let width = availableWidth > 0 ? availableWidth : defaultFallbackWidth
        return width / GuideAssetPlaceholder.defaultAspectRatio
    }

    private let defaultFallbackWidth: CGFloat = 320
}

/// Owns the AVPlayer + the loop observer. Removing the observer in `deinit`
/// (rather than only in `onDisappear`) guards against the leak path where a
/// view is torn down without `onDisappear` firing (e.g. navigation pop during
/// background).
private final class AVPlayerLoopController: NSObject {
    let avPlayer: AVPlayer
    private var loopObserver: NSObjectProtocol?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        avPlayer = player
        super.init()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.avPlayer.seek(to: .zero)
            self?.avPlayer.play()
        }
    }

    func detach() {
        avPlayer.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    deinit {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }
}

// MARK: - Previews

#Preview {
    GuideVideoPlayer(resourceName: "guide_imported_recipe_video")
        .padding(.horizontal, 20)
}
