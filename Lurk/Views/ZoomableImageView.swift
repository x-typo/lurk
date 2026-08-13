import SwiftUI
import UIKit

struct ZoomableImageView: View {
    let url: URL
    let isAnimated: Bool
    let isActive: Bool
    var posterURL: URL? = nil
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
                    Text("Couldn't load image")
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

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.onStateChange = { state in
            loadState = state
        }
        if isActive {
            context.coordinator.load(url: url, isAnimated: isAnimated, requestID: requestID)
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
            || context.coordinator.currentRequestID != requestID {
            context.coordinator.load(url: url, isAnimated: isAnimated, requestID: requestID)
        }
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var currentURL: URL?
        var currentIsAnimated: Bool = false
        var currentRequestID: UUID?
        var onStateChange: ((ZoomableImageView.LoadState) -> Void)?
        private var loadTask: Task<Void, Never>?

        deinit { loadTask?.cancel() }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale
        }

        func load(url: URL, isAnimated: Bool, requestID: UUID) {
            loadTask?.cancel()
            imageView?.image = nil
            scrollView?.setZoomScale(scrollView?.minimumZoomScale ?? 1, animated: false)
            currentURL = url
            currentIsAnimated = isAnimated
            currentRequestID = requestID
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

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
            currentURL = nil
            currentRequestID = nil
            onStateChange = nil
            imageView?.image = nil
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
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
