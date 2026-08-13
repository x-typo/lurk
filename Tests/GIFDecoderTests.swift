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
        #expect(abs(decoded.image.duration - 0.2) < 0.001)
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

    @Test("Playback timing matches the system-clamped GIF delay")
    func clampsFastPlaybackAndPreservesNormalDelays() {
        #expect(GIFDecoder.playbackDuration(clamped: 0.02, unclamped: 0.02) == 0.1)
        #expect(GIFDecoder.playbackDuration(clamped: nil, unclamped: 0.01) == 0.1)
        #expect(GIFDecoder.playbackDuration(clamped: 0.25, unclamped: 0.01) == 0.25)
        #expect(GIFDecoder.playbackDuration(clamped: .infinity, unclamped: nil) == 0.1)
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
