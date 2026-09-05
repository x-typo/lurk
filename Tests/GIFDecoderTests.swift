import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Lurk

@Suite("GIF resource limits")
struct GIFDecoderTests {
    @Test("Exact byte, frame, dimension, and pixel budgets are accepted")
    func acceptsExactBudgets() throws {
        let limits = limits(
            encodedBytes: 10,
            frameCount: 2,
            dimension: 2,
            pixelsPerFrame: 4,
            totalPixels: 8
        )

        try GIFDecoder.validate(
            encodedByteCount: 10,
            frames: [
                .init(pixelWidth: 2, pixelHeight: 2),
                .init(pixelWidth: 2, pixelHeight: 2),
            ],
            limits: limits
        )
    }

    @Test("Encoded data over budget is rejected before decoding")
    func rejectsEncodedDataOverBudget() {
        let limits = limits(encodedBytes: 4)

        let failure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 5,
                frames: [.init(pixelWidth: 1, pixelHeight: 1)],
                limits: limits
            )
        }

        #expect(failure == .encodedDataTooLarge(actual: 5, limit: 4))
    }

    @Test("Frame count over budget is rejected")
    func rejectsFrameCountOverBudget() {
        let limits = limits(frameCount: 2)

        let failure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: Array(repeating: .init(pixelWidth: 1, pixelHeight: 1), count: 3),
                limits: limits
            )
        }

        #expect(failure == .frameCountExceeded(actual: 3, limit: 2))
    }

    @Test("Oversized frame dimensions are rejected")
    func rejectsOversizedFrameDimensions() {
        let limits = limits(dimension: 2)

        let failure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: [.init(pixelWidth: 3, pixelHeight: 1)],
                limits: limits
            )
        }

        #expect(failure == .frameDimensionExceeded(index: 0, actual: 3, limit: 2))
    }

    @Test("Per-frame pixel budget is enforced")
    func rejectsOversizedFramePixelCount() {
        let limits = limits(dimension: 10, pixelsPerFrame: 5)

        let failure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: [.init(pixelWidth: 3, pixelHeight: 2)],
                limits: limits
            )
        }

        #expect(failure == .framePixelsExceeded(index: 0, actual: 6, limit: 5))
    }

    @Test("Aggregate decoded-pixel budget is enforced")
    func rejectsAggregatePixelCount() {
        let limits = limits(
            frameCount: 2,
            dimension: 10,
            pixelsPerFrame: 10,
            totalPixels: 7
        )

        let failure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: [
                    .init(pixelWidth: 2, pixelHeight: 2),
                    .init(pixelWidth: 2, pixelHeight: 2),
                ],
                limits: limits
            )
        }

        #expect(failure == .totalPixelsExceeded(atFrame: 1, actual: 8, limit: 7))
    }

    @Test("A GIF can exceed the inline budget while remaining valid fullscreen")
    func separatesInlineAndFullscreenBudgets() throws {
        let frames = Array(
            repeating: GIFDecoder.FrameMetadata(pixelWidth: 512, pixelHeight: 512),
            count: 31
        )

        let inlineFailure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: frames,
                limits: .inline
            )
        }
        #expect(inlineFailure == .totalPixelsExceeded(
            atFrame: 30,
            actual: 8_126_464,
            limit: 8_000_000
        ))

        try GIFDecoder.validate(
            encodedByteCount: 1,
            frames: frames,
            limits: .default
        )
    }

    @Test("Oversized inline GIFs can open the expanded viewer")
    func oversizedGIFsAllowMediaPresentation() {
        #expect(AnimatedGIFView.LoadState.loading.allowsMediaPresentation)
        #expect(AnimatedGIFView.LoadState.loaded.allowsMediaPresentation)
        #expect(AnimatedGIFView.LoadState.tooLarge.allowsMediaPresentation)
        #expect(!AnimatedGIFView.LoadState.failed.allowsMediaPresentation)
    }

    @Test("Invalid dimensions and pixel arithmetic overflow fail closed")
    func rejectsInvalidDimensionsAndOverflow() {
        let invalidFailure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: [.init(pixelWidth: 0, pixelHeight: 1)],
                limits: limits()
            )
        }
        #expect(invalidFailure == .invalidFrameDimensions(index: 0))

        let overflowLimits = limits(
            dimension: .max,
            pixelsPerFrame: .max,
            totalPixels: .max
        )
        let overflowFailure = gifFailure {
            try GIFDecoder.validate(
                encodedByteCount: 1,
                frames: [.init(pixelWidth: .max, pixelHeight: 2)],
                limits: overflowLimits
            )
        }
        #expect(overflowFailure == .framePixelCountOverflow(index: 0))
    }

    @Test("Invalid bytes are rejected")
    func rejectsInvalidBytes() {
        let failure = gifFailure {
            try GIFDecoder.image(from: Data([0x00, 0x01, 0x02]))
        }

        #expect(failure == .invalidImageData)
    }

    @Test("A valid two-frame GIF decodes as an animation")
    func decodesAnimatedGIF() throws {
        let data = try makeGIF(width: 2, height: 2, frameCount: 2, delay: 0.05)
        let decoded = try GIFDecoder.image(from: data)

        #expect(decoded.image.images?.count == 2)
        #expect(abs(decoded.image.duration - 0.1) < 0.001)
    }

    @Test("A modest GIF over the aggregate source budget animates within the output budget")
    func downsamplesGIFWithinInlineBudget() throws {
        let data = try makeGIF(width: 512, height: 512, frameCount: 31, delay: 0.05)
        let decoded = try GIFDecoder.image(from: data, limits: .inline)
        let frames = try #require(decoded.image.images)
        let metadata = try frames.map { frame in
            let image = try #require(frame.cgImage)
            #expect(image.width < 512)
            #expect(image.width == image.height)
            return GIFDecoder.FrameMetadata(pixelWidth: image.width, pixelHeight: image.height)
        }

        #expect(frames.count == 31)
        #expect(abs(decoded.image.duration - 1.55) < 0.001)
        try GIFDecoder.validate(encodedByteCount: data.count, frames: metadata, limits: .inline)
        #expect(metadata.reduce(0) { $0 + $1.pixelWidth * $1.pixelHeight }
                <= GIFDecoder.Limits.inline.maximumTotalDecodedPixels)
    }

    @Test("Adaptive decoding retains unequal frame timing")
    func downsamplingPreservesVariableTiming() throws {
        let data = try makeGIF(width: 20, height: 10, delays: [0.05, 0.15])
        let resourceLimits = limits(
            encodedBytes: data.count,
            frameCount: 2,
            dimension: 20,
            pixelsPerFrame: 200,
            totalPixels: 100
        )
        let decoded = try GIFDecoder.image(from: data, limits: resourceLimits)
        let frames = try #require(decoded.image.images)

        #expect(frames.count == 4)
        #expect(abs(decoded.image.duration - 0.2) < 0.001)
        #expect(frames.allSatisfy { ($0.cgImage?.width ?? 20) < 20 })
    }

    @Test("Adaptive GIF thumbnails preserve partial-frame transparency and disposal")
    func adaptiveDecodingPreservesFrameComposition() throws {
        let data = try compositionGIF()
        let original = try GIFDecoder.image(from: data)
        let adaptive = try GIFDecoder.image(from: data, limits: limits(
            encodedBytes: data.count,
            frameCount: 4,
            dimension: 16,
            pixelsPerFrame: 256,
            totalPixels: 256
        ))
        let originalFrames = try #require(original.image.images)
        let adaptiveFrames = try #require(adaptive.image.images)
        try #require(originalFrames.count == 4)
        try #require(adaptiveFrames.count == 4)
        #expect(abs(adaptive.image.duration - original.image.duration) < 0.001)

        let red: [UInt8] = [255, 0, 0, 255]
        let green: [UInt8] = [0, 255, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let clear: [UInt8] = [0, 0, 0, 0]
        let expectedSamples = [
            [red, red, red, red, red],
            [green, red, red, red, red],
            [clear, blue, red, red, red],
            [clear, red, green, red, red],
        ]
        for index in originalFrames.indices {
            let fullImage = try #require(originalFrames[index].cgImage)
            let smallImage = try #require(adaptiveFrames[index].cgImage)
            #expect(fullImage.width == 16 && fullImage.height == 16)
            #expect(smallImage.width == 8 && smallImage.height == 8)
            let fullSamples = try compositionSamples(from: fullImage)
            let smallSamples = try compositionSamples(from: smallImage)
            #expect(fullSamples == expectedSamples[index])
            for (fullPixel, smallPixel) in zip(fullSamples, smallSamples) {
                // Interior samples avoid filter edges; allow only channel-rounding noise.
                #expect(zip(fullPixel, smallPixel).allSatisfy {
                    abs(Int($0.0) - Int($0.1)) <= 2
                })
            }
        }
    }

    @Test("Long GIFs preserve the full timeline under retained-frame and pixel caps", arguments: [121, 240])
    func samplesLongGIFsWithinResourceBudgets(sourceFrameCount: Int) throws {
        var delays = Array(repeating: 0.05, count: sourceFrameCount)
        delays[sourceFrameCount - 1] = 0.35
        let data = try makeGIF(width: 320, height: 240, delays: delays)
        let decoded = try GIFDecoder.image(from: data, limits: .inline)
        let frames = try #require(decoded.image.images)
        let images = try frames.map { try #require($0.cgImage) }
        var seen = Set<ObjectIdentifier>()
        let retainedImages = images.filter { seen.insert(ObjectIdentifier($0)).inserted }

        #expect(abs(decoded.image.duration - delays.reduce(0, +)) < 0.001)
        #expect(retainedImages.count <= GIFDecoder.Limits.inline.maximumFrameCount)
        #expect(frames.count <= GIFDecoder.Limits.inline.maximumPlaybackFrameCount)
        #expect(retainedImages.count > 1)
        #expect(retainedImages.allSatisfy { $0.width < 320 })
        try GIFDecoder.validate(encodedByteCount: data.count, frames: retainedImages.map {
            .init(pixelWidth: $0.width, pixelHeight: $0.height)
        }, limits: .inline)
    }

    @Test("Sampling retains a long-held final image rather than the preceding transition")
    func samplingPreservesDominantFinalFrame() throws {
        let delays = Array(repeating: 0.02, count: 120) + [60.0]
        // The fixture alternates red/green: source119 is green, source120 is red.
        let data = try makeGIF(width: 2, height: 2, delays: delays)
        let decoded = try GIFDecoder.image(from: data, limits: .inline)
        let frames = try #require(decoded.image.images)
        let lastImage = try #require(frames.last?.cgImage)
        let red: [UInt8] = [255, 0, 0, 255]
        #expect(try compositionSamples(from: lastImage).first == red)

        var redFrameCount = 0
        for frame in frames {
            let image = try #require(frame.cgImage)
            if try compositionSamples(from: image).first == red {
                redFrameCount += 1
            }
        }
        #expect(redFrameCount * 5 > frames.count * 4)
        #expect(abs(decoded.image.duration - 62.4) < 0.001)
        #expect(frames.count <= GIFDecoder.Limits.inline.maximumPlaybackFrameCount)
    }

    @Test("Sampled GIF frames include skipped transparency and disposal operations")
    func sampledFramesPreserveCompositionAndTimeline() throws {
        let data = try compositionGIF(appendingTransparentFrame: true)
        let originalFrames = try #require(GIFDecoder.image(from: data).image.images)
        let sampled = try GIFDecoder.image(from: data, limits: limits(
            encodedBytes: data.count,
            frameCount: 3,
            dimension: 16,
            pixelsPerFrame: 256,
            totalPixels: 192
        ))
        let sampledFrames = try #require(sampled.image.images)
        try #require(originalFrames.count == 5)
        try #require(sampledFrames.count == 5)
        #expect(abs(sampled.image.duration - 0.5) < 0.001)

        // Contiguous groups 0..<1, 1..<3, 3..<5 retain 0/1/3 for 0.1/0.2/0.2 seconds.
        // Source frame 2 is skipped, but its restore-previous disposal must affect frame 3.
        let sourceIndices = [0, 1, 1, 3, 3]
        for (playbackIndex, sourceIndex) in sourceIndices.enumerated() {
            let reference = try #require(originalFrames[sourceIndex].cgImage)
            let thumbnail = try #require(sampledFrames[playbackIndex].cgImage)
            #expect(thumbnail.width == 8 && thumbnail.height == 8)
            let expected = try compositionSamples(from: reference)
            let observed = try compositionSamples(from: thumbnail)
            for (fullPixel, smallPixel) in zip(expected, observed) {
                #expect(zip(fullPixel, smallPixel).allSatisfy {
                    abs(Int($0.0) - Int($0.1)) <= 2
                })
            }
        }
    }

    @Test("Frame sampling rejects unusable budgets without dividing by zero")
    func frameSamplingRejectsInvalidBudgets() throws {
        #expect(GIFDecoder.frameGroups(sourceFrameCount: 0, maximumFrameCount: 120).isEmpty)
        #expect(GIFDecoder.frameGroups(sourceFrameCount: 601, maximumFrameCount: 120).isEmpty)
        #expect(GIFDecoder.frameGroups(sourceFrameCount: 5, maximumFrameCount: 0).isEmpty)
        let data = try makeGIF(width: 2, height: 2, frameCount: 2, delay: 0.05)
        for frameCount in [0, -1] {
            #expect(gifFailure {
                try GIFDecoder.image(from: data, limits: limits(encodedBytes: data.count, frameCount: frameCount))
            } == .imageAssemblyFailed)
        }
    }

    @Test("Adaptive decoding keeps hard source frame and dimension guards")
    func adaptiveDecodingRejectsExcessiveSourceWork() throws {
        let tooManyFrames = try makeGIF(width: 2, height: 2, frameCount: 601, delay: 0.05)
        #expect(gifFailure {
            try GIFDecoder.image(from: tooManyFrames, limits: .inline)
        } == .frameCountExceeded(actual: 601, limit: 600))

        let tooWide = try makeGIF(width: 2_049, height: 1, frameCount: 1, delay: 0.05)
        #expect(gifFailure {
            try GIFDecoder.image(from: tooWide, limits: .inline)
        } == .frameDimensionExceeded(index: 0, actual: 2_049, limit: 2_048))
    }

    @Test("Unequal frame delays retain their playback proportions")
    func preservesVariableFrameDelays() throws {
        let data = try makeGIF(width: 2, height: 2, delays: [0.1, 0.3])
        let decoded = try GIFDecoder.image(from: data)

        #expect(GIFDecoder.playbackFrameIndices(
            durations: [0.1, 0.3],
            maximumFrameCount: 600
        ) == [0, 1, 1, 1])
        #expect(decoded.image.images?.count == 4)
        #expect(abs(decoded.image.duration - 0.4) < 0.001)

        let cappedIndices = GIFDecoder.playbackFrameIndices(
            durations: [0.1, 60],
            maximumFrameCount: 600
        )
        #expect(cappedIndices.count == 600)
        #expect(cappedIndices.count(where: { $0 == 0 }) == 1)
        #expect(cappedIndices.count(where: { $0 == 1 }) == 599)
    }

    @Test("Valid fast GIF delays are preserved and pathological delays are bounded")
    func clampsFastPlaybackAndPreservesNormalDelays() {
        #expect(GIFDecoder.playbackDuration(clamped: 0.02, unclamped: 0.02) == 0.02)
        #expect(GIFDecoder.playbackDuration(clamped: 0.05, unclamped: 0.05) == 0.05)
        #expect(GIFDecoder.playbackDuration(clamped: nil, unclamped: 0.01) == 0.1)
        #expect(GIFDecoder.playbackDuration(clamped: 0.25, unclamped: 0.01) == 0.25)
        #expect(GIFDecoder.playbackDuration(clamped: .infinity, unclamped: nil) == 0.1)
        #expect(GIFDecoder.playbackDuration(clamped: -1, unclamped: nil) == 0.1)
        #expect(GIFDecoder.playbackDuration(clamped: 90, unclamped: nil) == 60)
    }

    @Test("Bare and Markdown GIF URLs use the bounded GIF renderer")
    func routesDirectGIFURLsThroughGIFRenderer() {
        let bareParts = CommentBodyView.parse("https://example.com/media/loop.gif?size=large")
        guard let barePart = bareParts.first, case .gif(let bareURL) = barePart else {
            Issue.record("Expected bare GIF URL to produce a GIF body part")
            return
        }
        #expect(bareURL.pathExtension == "gif")

        let markdownParts = CommentBodyView.parse(
            "[animation](https://example.com/media/loop.GIF?source=comment)"
        )
        guard let markdownPart = markdownParts.first,
              case .gif(let markdownURL) = markdownPart else {
            Issue.record("Expected Markdown GIF URL to produce a GIF body part")
            return
        }
        #expect(markdownURL.pathExtension == "GIF")

        let imageParts = CommentBodyView.parse("https://example.com/media/still.png")
        guard let imagePart = imageParts.first, case .image = imagePart else {
            Issue.record("Expected a non-GIF image to remain a static image body part")
            return
        }

        let punctuatedParts = CommentBodyView.parse("https://example.com/media/loop.gif, next")
        guard punctuatedParts.count == 3,
              case .gif(let punctuatedURL) = punctuatedParts[0],
              case .text(let punctuation) = punctuatedParts[1],
              case .text(let remainder) = punctuatedParts[2] else {
            Issue.record("Expected punctuation after a bare GIF URL to remain prose")
            return
        }
        #expect(punctuatedURL.pathExtension == "gif")
        #expect(punctuation == ",")
        #expect(remainder == " next")

        for punctuation in ["]", "…", "”"] {
            let parts = CommentBodyView.parse(
                "https://example.com/media/loop.gif\(punctuation) next"
            )
            guard parts.count == 3,
                  case .gif = parts[0],
                  case .text(let parsedPunctuation) = parts[1] else {
                Issue.record("Expected \(punctuation) after a GIF URL to remain prose")
                continue
            }
            #expect(parsedPunctuation == punctuation)
        }

        let ipv6Parts = CommentBodyView.parse("https://[2001:db8::1]")
        guard ipv6Parts.count == 1,
              case .link(_, let ipv6URL) = ipv6Parts[0] else {
            Issue.record("Expected a valid bracketed IPv6 URL to remain a link")
            return
        }
        #expect(ipv6URL.host?.contains(":") == true)

        for unsafeURL in [
            "file:///private/tmp/loop.gif",
            "ftp://example.com/loop.gif",
            "data:image/gif;base64,R0lGODlh",
            "[animation](file:///private/tmp/loop.gif)",
        ] {
            let unsafeParts = CommentBodyView.parse(unsafeURL)
            guard unsafeParts.count == 1,
                  case .text(let parsedText) = unsafeParts[0] else {
                Issue.record("Expected non-HTTP media URL to remain plain text")
                continue
            }
            #expect(parsedText == unsafeURL)
        }

        let multipleGIFParts = CommentBodyView.displayParts(
            from: "https://example.com/first.gif https://example.com/second.gif"
        )
        guard multipleGIFParts.count == 3,
              case .gif = multipleGIFParts[0],
              case .text = multipleGIFParts[1],
              case .link(let overflowTitle, let overflowURL) = multipleGIFParts[2] else {
            Issue.record("Expected only the first GIF in a body to render inline")
            return
        }
        #expect(overflowTitle == "Open GIF")
        #expect(overflowURL.lastPathComponent == "second.gif")
        #expect(GIFDecoder.Limits.inline.maximumTotalDecodedPixels == 8_000_000)
    }

    @Test("Shared load limiter serializes GIF frame expansion")
    func serializesGIFDecoding() async throws {
        let limiter = GIFLoadLimiter(maximumConcurrentLoads: 1)
        let firstGate = SuspensionGate()
        let first = Task {
            try await limiter.withPermit {
                await firstGate.waitUntilOpen()
                return 1
            }
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 0))

        let second = Task {
            try await limiter.withPermit { 2 }
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 1))

        await firstGate.open()
        #expect(try await first.value == 1)
        #expect(try await second.value == 2)
        #expect(await waitForSnapshot(limiter, active: 0, waiting: 0))
    }

    @Test("Visible GIF downloads can finish while frame expansion is serialized")
    func downloadsBeforeWaitingForDecodePermit() async throws {
        let data = try makeGIF(width: 2, height: 2, frameCount: 2, delay: 0.1)
        let limiter = GIFLoadLimiter(maximumConcurrentLoads: 1)
        let decodeGate = SuspensionGate()
        let downloads = DownloadProbe()

        let blocker = Task {
            try await limiter.withPermit {
                await decodeGate.waitUntilOpen()
                return true
            }
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 0))

        let first = Task {
            try await GIFImageLoader.load(limits: .inline, limiter: limiter) {
                await downloads.finish(data)
            }
        }
        let second = Task {
            try await GIFImageLoader.load(limits: .inline, limiter: limiter) {
                await downloads.finish(data)
            }
        }

        #expect(await waitForDownloadCount(downloads, count: 2))
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 2))

        await decodeGate.open()
        #expect(try await blocker.value)
        #expect(try await first.value.image.images?.count == 2)
        #expect(try await second.value.image.images?.count == 2)
        #expect(await waitForSnapshot(limiter, active: 0, waiting: 0))
    }

    @Test("Explicit playback has one active owner")
    @MainActor
    func explicitGIFPlaybackHasOneOwner() {
        let store = InlineGIFPlaybackStore()
        let first = UUID()
        let second = UUID()

        store.activate(first)
        #expect(store.activeIDs == [first])
        store.activate(second)
        #expect(store.activeIDs == [second])
        store.deactivate(first)
        #expect(store.activeIDs == [second])
        store.deactivate(second)
        #expect(store.activeIDs.isEmpty)
    }

    @Test("All meaningfully visible inline GIFs play and offscreen GIFs stop")
    @MainActor
    func inlinePlaybackFollowsVisibility() {
        let store = InlineGIFPlaybackStore()
        let first = UUID()
        let second = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        store.updateCandidate(
            first,
            frame: CGRect(x: 0, y: 0, width: 100, height: 40),
            viewport: viewport
        )
        #expect(store.activeIDs == [first])

        store.updateCandidate(
            second,
            frame: CGRect(x: 0, y: 40, width: 100, height: 40),
            viewport: viewport
        )
        #expect(store.activeIDs == [first, second])

        store.setCandidateEligible(false, id: first)
        #expect(store.activeIDs == [second])

        store.setCandidateEligible(true, id: first)
        #expect(store.activeIDs == [first, second])

        store.updateCandidate(
            second,
            frame: CGRect(x: 0, y: 120, width: 100, height: 40),
            viewport: viewport
        )
        #expect(store.activeIDs == [first])

        store.removeCandidate(first)
        #expect(store.activeIDs.isEmpty)
    }

    @Test("Inline playback uses visibility hysteresis at the viewport edge")
    @MainActor
    func inlinePlaybackUsesVisibilityHysteresis() {
        let store = InlineGIFPlaybackStore()
        let gif = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        store.updateCandidate(
            gif,
            frame: CGRect(x: 0, y: 95, width: 100, height: 100),
            viewport: viewport
        )
        #expect(store.activeIDs.isEmpty)

        store.updateCandidate(
            gif,
            frame: CGRect(x: 0, y: 80, width: 100, height: 100),
            viewport: viewport
        )
        #expect(store.activeIDs == [gif])

        store.updateCandidate(
            gif,
            frame: CGRect(x: 0, y: 85, width: 100, height: 100),
            viewport: viewport
        )
        #expect(store.activeIDs == [gif])

        store.updateCandidate(
            gif,
            frame: CGRect(x: 0, y: 91, width: 100, height: 100),
            viewport: viewport
        )
        #expect(store.activeIDs.isEmpty)
    }

    @Test("Explicit playback temporarily overrides visible feed candidates")
    @MainActor
    func explicitPlaybackOverridesCandidates() {
        let store = InlineGIFPlaybackStore()
        let feed = UUID()
        let detail = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        store.updateCandidate(
            feed,
            frame: CGRect(x: 0, y: 20, width: 100, height: 60),
            viewport: viewport
        )
        store.activate(detail)
        #expect(store.activeIDs == [detail])

        store.deactivate(detail)
        #expect(store.activeIDs == [feed])
    }

    @Test("Releasing a playback suspension resumes visible candidates")
    @MainActor
    func releasedPlaybackSuspensionResumesCandidates() async {
        let store = InlineGIFPlaybackStore()
        let feed = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)
        store.updateCandidate(
            feed,
            frame: CGRect(x: 0, y: 20, width: 100, height: 60),
            viewport: viewport
        )

        weak var releasedSuspension: InlineGIFPlaybackSuspension?
        do {
            let suspension = store.suspend()
            releasedSuspension = suspension
            #expect(store.activeIDs != [feed])
        }

        #expect(releasedSuspension == nil)
        #expect(await waitForActiveIDs(store, expected: [feed]))
    }

    @Test("Cancelling queued GIF loading releases its waiter")
    func cancelsQueuedGIFLoad() async throws {
        let limiter = GIFLoadLimiter(maximumConcurrentLoads: 1)
        let firstGate = SuspensionGate()
        let first = Task {
            try await limiter.withPermit {
                await firstGate.waitUntilOpen()
                return 1
            }
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 0))

        let queued = Task {
            try await limiter.withPermit { 2 }
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 1))
        queued.cancel()

        do {
            _ = try await queued.value
            Issue.record("Expected the queued GIF load to be cancelled")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await waitForSnapshot(limiter, active: 1, waiting: 0))

        await firstGate.open()
        #expect(try await first.value == 1)
        #expect(await waitForSnapshot(limiter, active: 0, waiting: 0))
    }

    @Test("Chunk collector accepts the exact byte boundary")
    func collectorAcceptsExactBoundary() throws {
        let data = try BoundedImageDataLoader.collect(
            [Data([1, 2]), Data([3, 4])],
            expectedContentLength: 4,
            maximumBytes: 4
        )

        #expect(Array(data) == [1, 2, 3, 4])
    }

    @Test("Chunk collector rejects a lying or absent content length")
    func collectorEnforcesObservedBytes() {
        do {
            _ = try BoundedImageDataLoader.collect(
                [Data([1, 2]), Data([3, 4, 5])],
                expectedContentLength: -1,
                maximumBytes: 4
            )
            Issue.record("Expected an observed-byte limit failure")
        } catch let failure as BoundedImageDataLoader.Failure {
            #expect(failure == .encodedDataTooLarge(actual: 5, limit: 4))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Chunk collector rejects an oversized declared length before reading")
    func collectorRejectsDeclaredLength() {
        do {
            _ = try BoundedImageDataLoader.collect(
                [Data](),
                expectedContentLength: 5,
                maximumBytes: 4
            )
            Issue.record("Expected a declared-length failure")
        } catch let failure as BoundedImageDataLoader.Failure {
            #expect(failure == .encodedDataTooLarge(actual: 5, limit: 4))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Chunk collector rejects an empty successful response")
    func collectorRejectsEmptyResponse() {
        do {
            _ = try BoundedImageDataLoader.collect(
                [Data](),
                expectedContentLength: 0,
                maximumBytes: 4
            )
            Issue.record("Expected an empty-response failure")
        } catch let failure as BoundedImageDataLoader.Failure {
            #expect(failure == .emptyResponse)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func limits(
        encodedBytes: Int = 100,
        frameCount: Int = 10,
        dimension: Int = 10,
        pixelsPerFrame: Int = 100,
        totalPixels: Int = 1_000,
        playbackFrames: Int = 600
    ) -> GIFDecoder.Limits {
        GIFDecoder.Limits(
            maximumEncodedBytes: encodedBytes,
            maximumFrameCount: frameCount,
            maximumPixelDimension: dimension,
            maximumPixelsPerFrame: pixelsPerFrame,
            maximumTotalDecodedPixels: totalPixels,
            maximumPlaybackFrameCount: playbackFrames
        )
    }

    private func gifFailure<Value>(_ operation: () throws -> Value) -> GIFDecoder.Failure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as GIFDecoder.Failure {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    private func waitForSnapshot(
        _ limiter: GIFLoadLimiter,
        active: Int,
        waiting: Int
    ) async -> Bool {
        for _ in 0..<1_000 {
            let snapshot = await limiter.snapshot()
            if snapshot == .init(activeLoads: active, waitingLoads: waiting) {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForDownloadCount(
        _ probe: DownloadProbe,
        count: Int
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await probe.completedCount() == count {
                return true
            }
            await Task.yield()
        }
        return false
    }

    @MainActor
    private func waitForActiveIDs(
        _ store: InlineGIFPlaybackStore,
        expected: Set<UUID>
    ) async -> Bool {
        for _ in 0..<1_000 {
            if store.activeIDs == expected {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func makeGIF(
        width: Int,
        height: Int,
        frameCount: Int,
        delay: Double
    ) throws -> Data {
        try makeGIF(
            width: width,
            height: height,
            delays: Array(repeating: delay, count: frameCount)
        )
    }

    private func makeGIF(
        width: Int,
        height: Int,
        delays: [Double]
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            delays.count,
            nil
        ) else {
            throw FixtureFailure.destinationCreation
        }

        for (index, delay) in delays.enumerated() {
            guard let image = makeImage(width: width, height: height, index: index) else {
                throw FixtureFailure.imageCreation
            }
            let gifProperties = [
                kCGImagePropertyGIFDelayTime: delay,
            ] as CFDictionary
            let properties = [
                kCGImagePropertyGIFDictionary: gifProperties,
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw FixtureFailure.finalization
        }
        return data as Data
    }

    private func makeImage(width: Int, height: Int, index: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(
            red: index.isMultiple(of: 2) ? 1 : 0,
            green: index.isMultiple(of: 2) ? 0 : 1,
            blue: 0,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func compositionGIF(appendingTransparentFrame: Bool = false) throws -> Data {
        // Authored GIF records: red canvas; green subrect with background disposal (2);
        // blue subrect with previous disposal (3); green/transparent final subrect.
        // The literal uses reset-delimited LZW codes, so an encoder cannot flatten it.
        var data = try #require(Data(base64Encoded: """
        R0lGODlhEAAQAIEAAAAAAP8AAAD/AAAA/yH5BAQKAAAALAAAAAAQABAAAALBDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwBQAh+QQJCgAAACwAAAAACAAIAAACMRRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFURRFUQUAIfkEDQoAAAAsCAAAAAgACAAAAjEcx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3EFACH5BAUKAAAALAAACAAIAAgAAAIxFEVRBEEQFEVRBEEQFEVRBEEQFEVRBEEQFEVRBEEQFEVRBEEQFEVRBEEQFEVRBEEQBQA7
        """, options: .ignoreUnknownCharacters))
        if appendingTransparentFrame {
            data.removeLast()
            // One transparent pixel leaves the previous canvas unchanged for a fifth frame.
            data.append(contentsOf: [
                0x21, 0xF9, 4, 5, 10, 0, 0, 0,
                0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
                2, 2, 0x44, 1, 0, 0x3B,
            ])
        }
        return data
    }

    private func compositionSamples(from image: CGImage) throws -> [[UInt8]] {
        let context = try #require(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // Coordinates in eighths cover background clearing, previous-frame restoration,
        // the opaque final subrect, its transparent half, and the untouched canvas.
        return [(1, 1), (5, 1), (1, 5), (3, 5), (5, 5)].map { x, y in
            let offset = ((y * image.height / 8) * image.width + x * image.width / 8) * 4
            return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
        }
    }

    private enum FixtureFailure: Error {
        case destinationCreation
        case imageCreation
        case finalization
    }

    private actor SuspensionGate {
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?

        func waitUntilOpen() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private actor DownloadProbe {
        private var count = 0

        func finish(_ data: Data) -> Data {
            count += 1
            return data
        }

        func completedCount() -> Int {
            count
        }
    }
}
