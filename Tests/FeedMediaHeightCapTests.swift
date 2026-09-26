import SwiftUI
import Testing
@testable import Lurk

@MainActor
@Suite("Feed media height cap")
struct FeedMediaHeightCapTests {
    @Test("Media taller than 4:5 is capped for the card's width, even without size metadata")
    func capsTallMedia() {
        // Hosting rounds to the display's pixel grid.
        #expect(abs(height(of: CGSize(width: 1080, height: 4000), width: 350) - 350 / Post.tallestFeedAspectRatio) < 0.5)
    }

    @Test("Wider media keeps its own shape")
    func keepsWideMedia() {
        #expect(abs(height(of: CGSize(width: 1600, height: 900), width: 350) - 196.875) < 0.5)
    }

    private func height(of pixels: CGSize, width: CGFloat) -> CGFloat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in }
        let view = FeedMediaHeightCap {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
        }
        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .infinity)).height
    }
}
