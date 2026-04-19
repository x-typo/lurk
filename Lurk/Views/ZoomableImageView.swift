import ImageIO
import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    let isAnimated: Bool

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
        context.coordinator.load(url: url, isAnimated: isAnimated)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.load(url: url, isAnimated: isAnimated)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var currentURL: URL?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Re-enable horizontal paging (TabView) swipes when fully zoomed out.
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale
        }

        func load(url: URL, isAnimated: Bool) {
            currentURL = url
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                let image = isAnimated ? Self.animatedImage(from: data) ?? UIImage(data: data) : UIImage(data: data)
                await MainActor.run { self?.imageView?.image = image }
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

        private static func animatedImage(from data: Data) -> UIImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let count = CGImageSourceGetCount(source)
            guard count > 1 else { return nil }

            var frames: [UIImage] = []
            var totalDuration: Double = 0
            for i in 0..<count {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                frames.append(UIImage(cgImage: cgImage))
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                        ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? Double
                        ?? 0.1
                    totalDuration += max(delay, 0.02)
                } else {
                    totalDuration += 0.1
                }
            }
            guard !frames.isEmpty else { return nil }
            return UIImage.animatedImage(with: frames, duration: totalDuration)
        }
    }
}
