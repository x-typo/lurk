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
    @State private var failed = false

    var body: some View {
        let isActive = scenePhase == .active && playbackStore.isActive(playbackID) && !failed

        ZStack {
            // A feed card's capped box can be wider than the video, which then fits inside it.
            Theme.background
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fit)
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
                isActive: isActive,
                onFailure: markFailed
            )
            .opacity(isActive ? 1 : 0)

            if failed {
                // Backed like a too-large GIF's notice, so it reads over the poster.
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text("Couldn't load GIF")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Button("Retry", action: retry)
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                }
                .padding(12)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }
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

extension InlineLoopingVideoView {
    // Like a GIF that fails to load: its candidate stops playing until Retry builds a new player.
    private func markFailed() {
        failed = true
        if activation == .whenVisible {
            playbackStore.setCandidateEligible(false, id: playbackID)
        }
    }

    private func retry() {
        if activation == .whenVisible {
            playbackStore.setCandidateEligible(true, id: playbackID)
        }
        failed = false
        requestID = UUID()
    }
}

private struct InlineLoopingVideoRepresentable: UIViewRepresentable {
    let url: URL
    let requestID: UUID
    let isActive: Bool
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        context.coordinator.playerView = view
        context.coordinator.onFailure = onFailure
        if isActive {
            context.coordinator.play(url: url, requestID: requestID)
        }
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        context.coordinator.playerView = view
        context.coordinator.onFailure = onFailure
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
        var onFailure: (() -> Void)?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var statusObservation: NSKeyValueObservation?

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
            // Only the current looper may report: a retired one's failure can arrive after its replacement starts.
            statusObservation = looper.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                let failedLooper = ObjectIdentifier(observed)
                Task { @MainActor [weak self] in
                    guard let self, let current = self.looper, ObjectIdentifier(current) == failedLooper else { return }
                    self.onFailure?()
                }
            }
            playerView?.playerLayer.player = player
            player.play()
        }

        func cancel() {
            statusObservation?.invalidate()
            statusObservation = nil
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

final class PlayerLayerView: UIView {
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
