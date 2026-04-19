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
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                let image = GIFDecoder.animatedImage(from: data) ?? UIImage(data: data)
                guard let image else { return }
                await MainActor.run { imageView.image = image }
            }
        }
    }
}
