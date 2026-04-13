import SwiftUI

struct GalleryDotIndicator: View {
    let count: Int

    private static let maxDots = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(count, Self.maxDots), id: \.self) { i in
                Circle()
                    .fill(i == 0 ? Color.white : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            if count > Self.maxDots {
                Text("+\(count - Self.maxDots)")
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
        .padding(.bottom, 10)
    }
}
