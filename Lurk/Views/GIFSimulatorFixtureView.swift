#if DEBUG
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GIFSimulatorFixtureView: View {
    private static let fixtureData = makeFixtureData(size: 240, frameCount: 3)
    private static let resourceLimitFixtureData = makeFixtureData(size: 512, frameCount: 31)
    @State private var playbackStore = InlineGIFPlaybackStore()
    @State private var showExpandedOversizedGIF = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Text("GIF playback fixture")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)

                    Text("Every GIF meaningfully on screen should animate. Offscreen GIFs should stop.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    fixtureCard(title: "First GIF")
                        .id("first")
                    fixtureCard(title: "Second GIF")
                        .id("second")
                    fixtureCard(title: "Third GIF")
                        .id("third")

                    VStack(spacing: 10) {
                        Text("Oversized GIF safety fallback")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Text("This sample exceeds the inline budget but fits the expanded viewer budget.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        if let data = Self.resourceLimitFixtureData {
                            AnimatedGIFView(data: data, activation: .whenVisible)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            Button("Play in expanded viewer") {
                                showExpandedOversizedGIF = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Show 1 + 2") {
                        proxy.scrollTo("first", anchor: .top)
                    }
                    Button("Show 2 + 3") {
                        proxy.scrollTo("second", anchor: .top)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .environment(playbackStore)
        .fullScreenCover(isPresented: $showExpandedOversizedGIF) {
            ZStack(alignment: .topTrailing) {
                Theme.background.ignoresSafeArea()

                if let data = Self.resourceLimitFixtureData {
                    AnimatedGIFView(
                        data: data,
                        limits: .default,
                        activation: .onAppear
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .padding(24)
                }

                Button("Close") {
                    showExpandedOversizedGIF = false
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .preferredColorScheme(.dark)
            .environment(playbackStore)
        }
    }

    @ViewBuilder
    private func fixtureCard(title: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            if let fixtureData = Self.fixtureData {
                AnimatedGIFView(data: fixtureData, activation: .whenVisible)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Couldn't create the GIF fixture")
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private static func makeFixtureData(size: CGFloat, frameCount: Int) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            return nil
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0,
                ],
            ] as CFDictionary
        )

        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 0.25,
            ],
        ] as CFDictionary

        let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue]
        for index in 0..<frameCount {
            let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image {
                let color = colors[index % colors.count]
                color.setFill()
                $0.fill(CGRect(x: 0, y: 0, width: size, height: size))
            }
            guard let cgImage = image.cgImage else { return nil }
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
