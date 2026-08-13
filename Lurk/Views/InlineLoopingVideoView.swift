import AVFoundation
import SwiftUI
import UIKit

struct InlineLoopingVideoView: View {
    let url: URL
    let posterURL: URL?
    let aspectRatio: CGFloat?
    var activation: AnimatedGIFView.Activation = .whenVisible

    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var playbackID = UUID()
    @State private var requestID = UUID()

    var body: some View {
        let isActive = scenePhase == .active && playbackStore.isActive(playbackID)

        ZStack {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Theme.surfaceElevated
                    }
                }
            } else {
                Theme.surfaceElevated
            }

            InlineLoopingVideoRepresentable(
                url: url,
                requestID: requestID,
                isActive: isActive
            )
            .opacity(isActive ? 1 : 0)
        }
        .aspectRatio(aspectRatio ?? 16 / 9, contentMode: .fit)
        .clipped()
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            guard activation == .whenVisible else { return }
            playbackStore.updateCandidate(playbackID, frame: frame)
        }
        .onAppear {
            if activation == .onAppear {
                playbackStore.activate(playbackID)
            }
        }
        .onDisappear {
            if activation == .onAppear {
                playbackStore.deactivate(playbackID)
            } else {
                playbackStore.removeCandidate(playbackID)
            }
        }
    }
}

private struct InlineLoopingVideoRepresentable: UIViewRepresentable {
    let url: URL
    let requestID: UUID
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        context.coordinator.playerView = view
        if isActive {
            context.coordinator.play(url: url, requestID: requestID)
        }
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        context.coordinator.playerView = view
        guard isActive else {
            context.coordinator.cancel()
            return
        }
        if context.coordinator.currentURL != url
            || context.coordinator.currentRequestID != requestID {
            context.coordinator.play(url: url, requestID: requestID)
        }
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: Coordinator) {
        coordinator.cancel()
        view.playerLayer.player = nil
    }

    @MainActor
    final class Coordinator {
        weak var playerView: PlayerLayerView?
        var currentURL: URL?
        var currentRequestID: UUID?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        deinit {
            looper?.disableLooping()
            player?.pause()
        }

        func play(url: URL, requestID: UUID) {
            cancel()
            currentURL = url
            currentRequestID = requestID

            let player = AVQueuePlayer()
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            self.player = player
            self.looper = looper
            playerView?.playerLayer.player = player
            player.play()
        }

        func cancel() {
            looper?.disableLooping()
            looper = nil
            player?.pause()
            player?.removeAllItems()
            player = nil
            playerView?.playerLayer.player = nil
            currentURL = nil
            currentRequestID = nil
        }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
