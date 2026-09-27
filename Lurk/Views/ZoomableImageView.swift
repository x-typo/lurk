import AVFoundation
import SwiftUI
import UIKit

struct ZoomableImageView: View {
    let url: URL
    let isAnimated: Bool
    let isActive: Bool
    var posterURL: URL? = nil
    // An animated item's MP4, played with a photo's zoom instead of decoding the GIF at `url`.
    var videoURL: URL? = nil
    var onLoadStateChange: ((LoadState) -> Void)? = nil
    @State private var loadState: LoadState = .loading
    @State private var requestID = UUID()

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
        case tooLarge
    }

    var body: some View {
        ZStack {
            if let posterURL, posterURL != url {
                AsyncImage(url: posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Theme.surfaceElevated
                    }
                }
            }

            ZoomableImageRepresentable(
                url: url,
                isAnimated: isAnimated,
                videoURL: videoURL,
                requestID: requestID,
                isActive: isActive,
                loadState: $loadState
            )
                .opacity(loadState == .loaded ? 1 : 0)
                .allowsHitTesting(isActive && loadState == .loaded)

            switch loadState {
            case .loading:
                ProgressView().tint(Theme.primary)
            case .failed:
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textMuted)
                    Text(videoURL == nil ? "Couldn't load image" : "Couldn't load GIF")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Button("Retry") {
                        loadState = .loading
                        requestID = UUID()
                    }
                    .font(.caption)
                }
            case .tooLarge:
                EmptyView()
            case .loaded:
                EmptyView()
            }
        }
        .onChange(of: loadState, initial: true) { _, state in
            onLoadStateChange?(state)
        }
    }
}

private struct ZoomableImageRepresentable: UIViewRepresentable {
    let url: URL
    let isAnimated: Bool
    let videoURL: URL?
    let requestID: UUID
    let isActive: Bool
    @Binding var loadState: ZoomableImageView.LoadState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        // Disabled until the user zooms in, so TabView paging owns horizontal swipes.
        scrollView.isScrollEnabled = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let playerView = PlayerLayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        scrollView.addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            playerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            playerView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        context.coordinator.playerView = playerView
        context.coordinator.scrollView = scrollView
        context.coordinator.onStateChange = { state in
            loadState = state
        }
        if isActive {
            context.coordinator.load(url: url, isAnimated: isAnimated, videoURL: videoURL, requestID: requestID)
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onStateChange = { state in
            loadState = state
        }
        guard isActive else {
            context.coordinator.cancel()
            return
        }
        if context.coordinator.currentURL != url
            || context.coordinator.currentIsAnimated != isAnimated
            || context.coordinator.currentVideoURL != videoURL
            || context.coordinator.currentRequestID != requestID {
            context.coordinator.load(url: url, isAnimated: isAnimated, videoURL: videoURL, requestID: requestID)
        }
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var playerView: PlayerLayerView?
        weak var scrollView: UIScrollView?
        var currentURL: URL?
        var currentIsAnimated: Bool = false
        var currentVideoURL: URL?
        var currentRequestID: UUID?
        var onStateChange: ((ZoomableImageView.LoadState) -> Void)?
        private var loadTask: Task<Void, Never>?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var playerObservations: [NSKeyValueObservation] = []

        deinit {
            loadTask?.cancel()
            looper?.disableLooping()
            player?.pause()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            currentVideoURL == nil ? imageView : playerView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale
        }

        func load(url: URL, isAnimated: Bool, videoURL: URL?, requestID: UUID) {
            loadTask?.cancel()
            stopVideo()
            imageView?.image = nil
            scrollView?.setZoomScale(scrollView?.minimumZoomScale ?? 1, animated: false)
            currentURL = url
            currentIsAnimated = isAnimated
            currentVideoURL = videoURL
            currentRequestID = requestID
            imageView?.isHidden = videoURL != nil
            playerView?.isHidden = videoURL == nil
            if let videoURL {
                playVideo(videoURL, requestID: requestID)
                return
            }
            loadTask = Task { [weak self] in
                guard let self,
                      self.currentURL == url,
                      self.currentIsAnimated == isAnimated,
                      self.currentRequestID == requestID else { return }
                self.onStateChange?(.loading)

                do {
                    let image: UIImage?
                    if isAnimated {
                        image = try await GIFImageLoader.load(from: url).image
                    } else {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        try Task.checkCancellation()
                        image = UIImage(data: data)
                    }
                    try Task.checkCancellation()
                    guard self.currentURL == url,
                          self.currentIsAnimated == isAnimated,
                          self.currentRequestID == requestID else { return }
                    if let image {
                        self.imageView?.image = image
                        self.onStateChange?(.loaded)
                    } else {
                        self.onStateChange?(.failed)
                    }
                } catch is CancellationError {
                } catch GIFImageLoader.Failure.tooLarge {
                    guard self.currentURL == url,
                          self.currentIsAnimated == isAnimated,
                          self.currentRequestID == requestID else { return }
                    self.onStateChange?(.tooLarge)
                } catch {
                    guard self.currentURL == url,
                          self.currentIsAnimated == isAnimated,
                          self.currentRequestID == requestID else { return }
                    self.onStateChange?(.failed)
                }
            }
        }

        private func playVideo(_ videoURL: URL, requestID: UUID) {
            onStateChange?(.loading)
            let player = AVQueuePlayer()
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: videoURL))
            self.player = player
            self.looper = looper
            playerView?.playerLayer.player = player
            // The page shows once the first frame is ready; the poster covers it until then. Reports are
            // bound to this player, since a retired one's can arrive after a reload reuses the request ID.
            let playerID = ObjectIdentifier(player)
            if let playerLayer = playerView?.playerLayer {
                playerObservations.append(playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                    guard layer.isReadyForDisplay else { return }
                    Task { @MainActor [weak self] in self?.finishVideo(.loaded, requestID: requestID, playerID: playerID) }
                })
            }
            playerObservations.append(looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                Task { @MainActor [weak self] in self?.finishVideo(.failed, requestID: requestID, playerID: playerID) }
            })
            player.play()
        }

        private func finishVideo(_ state: ZoomableImageView.LoadState, requestID: UUID, playerID: ObjectIdentifier) {
            guard currentRequestID == requestID, let player, ObjectIdentifier(player) == playerID else { return }
            onStateChange?(state)
        }

        private func stopVideo() {
            playerObservations.forEach { $0.invalidate() }
            playerObservations = []
            looper?.disableLooping()
            looper = nil
            player?.pause()
            player?.removeAllItems()
            player = nil
            playerView?.playerLayer.player = nil
        }

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
            stopVideo()
            currentURL = nil
            currentVideoURL = nil
            currentRequestID = nil
            onStateChange = nil
            imageView?.image = nil
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: viewForZooming(in: scrollView))
                let targetScale: CGFloat = 2.0
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                let rect = CGRect(
                    origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                    size: size
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

    }
}
