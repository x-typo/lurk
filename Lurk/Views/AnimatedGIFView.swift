import ImageIO
import SwiftUI
import UIKit

struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.load(url: url, into: imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        func load(url: URL, into imageView: UIImageView) {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

                let count = CGImageSourceGetCount(source)
                guard count > 1 else {
                    if let image = UIImage(data: data) {
                        await MainActor.run { imageView.image = image }
                    }
                    return
                }

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

                guard !frames.isEmpty else { return }
                let animated = UIImage.animatedImage(with: frames, duration: totalDuration)
                await MainActor.run {
                    imageView.image = animated
                }
            }
        }
    }
}
