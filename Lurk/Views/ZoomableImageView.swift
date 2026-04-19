import SwiftUI
import UIKit

struct ZoomableImageView: View {
    let url: URL
    let isAnimated: Bool
    @State private var loadState: LoadState = .loading

    enum LoadState: Equatable { case loading, loaded, failed }

    var body: some View {
        ZStack {
            ZoomableImageRepresentable(url: url, isAnimated: isAnimated, loadState: $loadState)
                .opacity(loadState == .loaded ? 1 : 0)

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
                }
            case .loaded:
                EmptyView()
            }
        }
    }
}

private struct ZoomableImageRepresentable: UIViewRepresentable {
    let url: URL
    let isAnimated: Bool
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
            Task { @MainActor in loadState = state }
        }
        context.coordinator.load(url: url, isAnimated: isAnimated)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onStateChange = { state in
            Task { @MainActor in loadState = state }
        }
        if context.coordinator.currentURL != url || context.coordinator.currentIsAnimated != isAnimated {
            context.coordinator.load(url: url, isAnimated: isAnimated)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var currentURL: URL?
        var currentIsAnimated: Bool = false
        var onStateChange: ((ZoomableImageView.LoadState) -> Void)?
        private var loadTask: Task<Void, Never>?

        deinit { loadTask?.cancel() }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale
        }

        func load(url: URL, isAnimated: Bool) {
            loadTask?.cancel()
            currentURL = url
            currentIsAnimated = isAnimated
            onStateChange?(.loading)
            loadTask = Task { [weak self] in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    try Task.checkCancellation()
                    let image = isAnimated
                        ? GIFDecoder.animatedImage(from: data) ?? UIImage(data: data)
                        : UIImage(data: data)
                    await MainActor.run {
                        guard let self, self.currentURL == url else { return }
                        if let image {
                            self.imageView?.image = image
                            self.onStateChange?(.loaded)
                        } else {
                            self.onStateChange?(.failed)
                        }
                    }
                } catch is CancellationError {
                } catch {
                    await MainActor.run {
                        guard let self, self.currentURL == url else { return }
                        self.onStateChange?(.failed)
                    }
                }
            }
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
