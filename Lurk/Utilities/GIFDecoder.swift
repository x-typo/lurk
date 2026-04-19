import ImageIO
import UIKit

enum GIFDecoder {
    static func animatedImage(from data: Data) -> UIImage? {
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
