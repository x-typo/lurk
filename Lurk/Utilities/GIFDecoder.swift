import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

nonisolated enum BoundedImageDataLoader {
    enum Failure: Error, Equatable {
        case invalidMaximumBytes
        case httpStatus(Int)
        case encodedDataTooLarge(actual: Int64, limit: Int)
        case emptyResponse
    }

    static func data(
        from url: URL,
        maximumBytes: Int
    ) async throws -> Data {
        guard maximumBytes > 0 else { throw Failure.invalidMaximumBytes }
        return try await BoundedImageDataSession.shared.data(
            from: url,
            maximumBytes: maximumBytes
        )
    }

    static func data(
        from url: URL,
        maximumBytes: Int,
        configuration: URLSessionConfiguration
    ) async throws -> Data {
        guard maximumBytes > 0 else { throw Failure.invalidMaximumBytes }
        let session = BoundedImageDataSession(configuration: configuration)
        defer { session.invalidate() }
        return try await session.data(from: url, maximumBytes: maximumBytes)
    }

    static func collect<Chunks: Sequence>(
        _ chunks: Chunks,
        expectedContentLength: Int64,
        maximumBytes: Int
    ) throws -> Data where Chunks.Element == Data {
        guard maximumBytes > 0 else { throw Failure.invalidMaximumBytes }
        if expectedContentLength > Int64(maximumBytes) {
            throw Failure.encodedDataTooLarge(
                actual: expectedContentLength,
                limit: maximumBytes
            )
        }

        var data = Data()
        if expectedContentLength > 0 {
            data.reserveCapacity(Int(expectedContentLength))
        }

        for chunk in chunks {
            if let failure = append(chunk, to: &data, maximumBytes: maximumBytes) {
                throw failure
            }
        }
        guard !data.isEmpty else { throw Failure.emptyResponse }
        return data
    }

    static func append(
        _ chunk: Data,
        to data: inout Data,
        maximumBytes: Int
    ) -> Failure? {
        let actual = Int64(data.count) + Int64(chunk.count)
        guard actual <= Int64(maximumBytes) else {
            return .encodedDataTooLarge(
                actual: actual,
                limit: maximumBytes
            )
        }
        data.append(chunk)
        return nil
    }
}

nonisolated final class BoundedImageDataSession:
    NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    static let shared = BoundedImageDataSession(configuration: .default)

    private struct Transfer {
        let continuation: CheckedContinuation<Data, any Error>
        let task: URLSessionDataTask
        let maximumBytes: Int
        var data = Data()
    }

    private struct State {
        var transfers: [UUID: Transfer] = [:]
        var requestIDsByTaskIdentifier: [Int: UUID] = [:]
        var cancelledRequestIDs: Set<UUID> = []
        var isInvalidated = false
    }

    private struct Completion {
        let continuation: CheckedContinuation<Data, any Error>
        let task: URLSessionDataTask
        let result: Result<Data, any Error>
        let cancelUnderlyingTask: Bool
    }

    private let lock = NSLock()
    private let cancellationObserver: (@Sendable (URLSessionTask) -> Void)?
    private var state = State()
    private var session: URLSession!

    init(
        configuration: URLSessionConfiguration,
        cancellationObserver: (@Sendable (URLSessionTask) -> Void)? = nil
    ) {
        self.cancellationObserver = cancellationObserver
        super.init()
        let configuration = configuration.copy() as? URLSessionConfiguration ?? configuration
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func data(from url: URL, maximumBytes: Int) async throws -> Data {
        guard maximumBytes > 0 else {
            throw BoundedImageDataLoader.Failure.invalidMaximumBytes
        }
        try Task.checkCancellation()
        let requestID = UUID()
        defer { clearCancellationMarker(requestID) }

        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, any Error>) in
                let task = withLock { state -> URLSessionDataTask? in
                    guard !state.isInvalidated,
                          state.cancelledRequestIDs.remove(requestID) == nil else {
                        return nil
                    }
                    let task = session.dataTask(with: url)
                    state.transfers[requestID] = Transfer(
                        continuation: continuation,
                        task: task,
                        maximumBytes: maximumBytes
                    )
                    state.requestIDsByTaskIdentifier[task.taskIdentifier] = requestID
                    return task
                }

                if let task {
                    task.resume()
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancel(requestID)
        }
        try Task.checkCancellation()
        return data
    }

    func invalidate() {
        let completions = withLock { state -> [Completion] in
            guard !state.isInvalidated else { return [] }
            state.isInvalidated = true
            let completions = state.transfers.values.map {
                Completion(
                    continuation: $0.continuation,
                    task: $0.task,
                    result: .failure(CancellationError()),
                    cancelUnderlyingTask: true
                )
            }
            state.transfers.removeAll()
            state.requestIDsByTaskIdentifier.removeAll()
            state.cancelledRequestIDs.removeAll()
            return completions
        }
        session.invalidateAndCancel()
        completions.forEach(deliver)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let decision = withLock { state -> (Bool, BoundedImageDataLoader.Failure?) in
            guard let requestID = state.requestIDsByTaskIdentifier[dataTask.taskIdentifier],
                  var transfer = state.transfers[requestID] else {
                return (false, nil)
            }
            if let response = response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                return (false, .httpStatus(response.statusCode))
            }
            if response.expectedContentLength > Int64(transfer.maximumBytes) {
                return (false, .encodedDataTooLarge(
                    actual: response.expectedContentLength,
                    limit: transfer.maximumBytes
                ))
            }
            if response.expectedContentLength > 0 {
                transfer.data.reserveCapacity(Int(response.expectedContentLength))
                state.transfers[requestID] = transfer
            }
            return (true, nil)
        }

        if let failure = decision.1 {
            completionHandler(.cancel)
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                result: .failure(failure),
                cancelUnderlyingTask: true
            )
        } else if decision.0 {
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let failure = withLock { state -> BoundedImageDataLoader.Failure? in
            guard let requestID = state.requestIDsByTaskIdentifier[dataTask.taskIdentifier],
                  var transfer = state.transfers.removeValue(forKey: requestID) else {
                return nil
            }
            // Keep one owner of the buffer while appending, avoiding a full Data copy per chunk.
            let failure = BoundedImageDataLoader.append(
                data,
                to: &transfer.data,
                maximumBytes: transfer.maximumBytes
            )
            state.transfers[requestID] = transfer
            return failure
        }

        if let failure {
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                result: .failure(failure),
                cancelUnderlyingTask: true
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            finish(
                taskIdentifier: task.taskIdentifier,
                result: .failure(error),
                cancelUnderlyingTask: false
            )
            return
        }

        let result = withLock { state -> Result<Data, any Error>? in
            guard let requestID = state.requestIDsByTaskIdentifier[task.taskIdentifier],
                  let transfer = state.transfers[requestID] else {
                return nil
            }
            return transfer.data.isEmpty
                ? .failure(BoundedImageDataLoader.Failure.emptyResponse)
                : .success(transfer.data)
        }
        if let result {
            finish(
                taskIdentifier: task.taskIdentifier,
                result: result,
                cancelUnderlyingTask: false
            )
        }
    }

    private func cancel(_ requestID: UUID) {
        let completion = withLock { state -> Completion? in
            guard let transfer = state.transfers.removeValue(forKey: requestID) else {
                if !state.isInvalidated {
                    state.cancelledRequestIDs.insert(requestID)
                }
                return nil
            }
            state.requestIDsByTaskIdentifier.removeValue(forKey: transfer.task.taskIdentifier)
            return Completion(
                continuation: transfer.continuation,
                task: transfer.task,
                result: .failure(CancellationError()),
                cancelUnderlyingTask: true
            )
        }
        deliver(completion)
    }

    private func finish(
        taskIdentifier: Int,
        result: Result<Data, any Error>,
        cancelUnderlyingTask: Bool
    ) {
        let completion = withLock { state -> Completion? in
            guard let requestID = state.requestIDsByTaskIdentifier.removeValue(
                forKey: taskIdentifier
            ), let transfer = state.transfers.removeValue(forKey: requestID) else {
                return nil
            }
            return Completion(
                continuation: transfer.continuation,
                task: transfer.task,
                result: result,
                cancelUnderlyingTask: cancelUnderlyingTask
            )
        }
        deliver(completion)
    }

    private func deliver(_ completion: Completion?) {
        guard let completion else { return }
        if completion.cancelUnderlyingTask {
            completion.task.cancel()
            cancellationObserver?(completion.task)
        }
        completion.continuation.resume(with: completion.result)
    }

    private func clearCancellationMarker(_ requestID: UUID) {
        _ = withLock { state in
            state.cancelledRequestIDs.remove(requestID)
        }
    }

    private func withLock<Value>(_ operation: (inout State) -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation(&state)
    }
}

actor GIFLoadLimiter {
    struct Snapshot: Equatable, Sendable {
        let activeLoads: Int
        let waitingLoads: Int
    }

    static let shared = GIFLoadLimiter(maximumConcurrentLoads: 1)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let maximumConcurrentLoads: Int
    private var activeLoads = 0
    private var waiters: [Waiter] = []

    init(maximumConcurrentLoads: Int) {
        precondition(maximumConcurrentLoads > 0)
        self.maximumConcurrentLoads = maximumConcurrentLoads
    }

    func withPermit<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await acquirePermit()
        defer { releasePermit() }
        try Task.checkCancellation()
        return try await operation()
    }

    func snapshot() -> Snapshot {
        Snapshot(activeLoads: activeLoads, waitingLoads: waiters.count)
    }

    private func acquirePermit() async throws {
        try Task.checkCancellation()
        if activeLoads < maximumConcurrentLoads {
            activeLoads += 1
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releasePermit() {
        if waiters.isEmpty {
            activeLoads -= 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
        }
    }
}

nonisolated enum GIFDecoder {
    // Bounds metadata inspection and ImageIO composition work independently of retained frames.
    static let maximumSourceFrameCount = 600

    struct Limits: Equatable, Sendable {
        let maximumEncodedBytes: Int
        // Unique decoded frames retained for playback; longer sources are sampled.
        let maximumFrameCount: Int
        let maximumPixelDimension: Int
        let maximumPixelsPerFrame: Int
        let maximumTotalDecodedPixels: Int
        let maximumPlaybackFrameCount: Int

        static let `default` = Limits(
            maximumEncodedBytes: 12 * 1_024 * 1_024,
            maximumFrameCount: 120,
            maximumPixelDimension: 4_096,
            maximumPixelsPerFrame: 3_000_000,
            maximumTotalDecodedPixels: 18_000_000,
            maximumPlaybackFrameCount: 600
        )

        static let inline = Limits(
            maximumEncodedBytes: 8 * 1_024 * 1_024,
            maximumFrameCount: 120,
            maximumPixelDimension: 2_048,
            maximumPixelsPerFrame: 1_500_000,
            maximumTotalDecodedPixels: 8_000_000,
            maximumPlaybackFrameCount: 600
        )
    }

    struct FrameMetadata: Equatable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
    }

    enum Failure: Error, Equatable {
        case encodedDataTooLarge(actual: Int, limit: Int)
        case invalidImageData
        case unsupportedImageType
        case frameCountExceeded(actual: Int, limit: Int)
        case invalidFrameDimensions(index: Int)
        case frameDimensionExceeded(index: Int, actual: Int, limit: Int)
        case framePixelCountOverflow(index: Int)
        case framePixelsExceeded(index: Int, actual: Int, limit: Int)
        case totalPixelCountOverflow(index: Int)
        case totalPixelsExceeded(atFrame: Int, actual: Int, limit: Int)
        case frameDecodeFailed(index: Int)
        case imageAssemblyFailed

        var isResourceLimit: Bool {
            switch self {
            case .encodedDataTooLarge,
                 .frameCountExceeded,
                 .frameDimensionExceeded,
                 .framePixelCountOverflow,
                 .framePixelsExceeded,
                 .totalPixelCountOverflow,
                 .totalPixelsExceeded:
                true
            case .invalidImageData,
                 .unsupportedImageType,
                 .invalidFrameDimensions,
                 .frameDecodeFailed,
                 .imageAssemblyFailed:
                false
            }
        }
    }

    // UIImage instances created here are immutable before crossing back to the main actor.
    struct DecodedImage: @unchecked Sendable {
        let image: UIImage
    }

    static func validate(
        encodedByteCount: Int,
        frames: [FrameMetadata],
        limits: Limits = .default
    ) throws {
        guard encodedByteCount <= limits.maximumEncodedBytes else {
            throw Failure.encodedDataTooLarge(
                actual: encodedByteCount,
                limit: limits.maximumEncodedBytes
            )
        }
        guard !frames.isEmpty else { throw Failure.invalidImageData }
        guard frames.count <= limits.maximumFrameCount else {
            throw Failure.frameCountExceeded(
                actual: frames.count,
                limit: limits.maximumFrameCount
            )
        }

        var totalPixels = 0
        for (index, frame) in frames.enumerated() {
            guard frame.pixelWidth > 0, frame.pixelHeight > 0 else {
                throw Failure.invalidFrameDimensions(index: index)
            }

            let largestDimension = max(frame.pixelWidth, frame.pixelHeight)
            guard largestDimension <= limits.maximumPixelDimension else {
                throw Failure.frameDimensionExceeded(
                    index: index,
                    actual: largestDimension,
                    limit: limits.maximumPixelDimension
                )
            }

            let (framePixels, frameOverflow) = frame.pixelWidth.multipliedReportingOverflow(
                by: frame.pixelHeight
            )
            guard !frameOverflow else {
                throw Failure.framePixelCountOverflow(index: index)
            }
            guard framePixels <= limits.maximumPixelsPerFrame else {
                throw Failure.framePixelsExceeded(
                    index: index,
                    actual: framePixels,
                    limit: limits.maximumPixelsPerFrame
                )
            }

            let (newTotal, totalOverflow) = totalPixels.addingReportingOverflow(framePixels)
            guard !totalOverflow else {
                throw Failure.totalPixelCountOverflow(index: index)
            }
            guard newTotal <= limits.maximumTotalDecodedPixels else {
                throw Failure.totalPixelsExceeded(
                    atFrame: index,
                    actual: newTotal,
                    limit: limits.maximumTotalDecodedPixels
                )
            }
            totalPixels = newTotal
        }
    }

    static func image(
        from data: Data,
        limits: Limits = .default
    ) throws -> DecodedImage {
        guard data.count <= limits.maximumEncodedBytes else {
            throw Failure.encodedDataTooLarge(
                actual: data.count,
                limit: limits.maximumEncodedBytes
            )
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw Failure.invalidImageData
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw Failure.invalidImageData }
        guard let sourceType = CGImageSourceGetType(source),
              UTType(sourceType as String)?.conforms(to: .gif) == true else {
            throw Failure.unsupportedImageType
        }
        guard frameCount <= maximumSourceFrameCount else {
            throw Failure.frameCountExceeded(
                actual: frameCount,
                limit: maximumSourceFrameCount
            )
        }

        let groups = frameGroups(
            sourceFrameCount: frameCount,
            maximumFrameCount: min(limits.maximumFrameCount, limits.maximumPlaybackFrameCount)
        )
        guard !groups.isEmpty else { throw Failure.imageAssemblyFailed }

        let sourceLimits = Limits(
            maximumEncodedBytes: limits.maximumEncodedBytes,
            maximumFrameCount: maximumSourceFrameCount,
            maximumPixelDimension: limits.maximumPixelDimension,
            maximumPixelsPerFrame: limits.maximumPixelsPerFrame,
            maximumTotalDecodedPixels: .max,
            maximumPlaybackFrameCount: limits.maximumPlaybackFrameCount
        )
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
              let canvasWidth = gifProperties[kCGImagePropertyGIFCanvasPixelWidth as String] as? NSNumber,
              let canvasHeight = gifProperties[kCGImagePropertyGIFCanvasPixelHeight as String] as? NSNumber else {
            throw Failure.invalidImageData
        }
        try validate(encodedByteCount: data.count, frames: [
            .init(pixelWidth: canvasWidth.intValue, pixelHeight: canvasHeight.intValue)
        ], limits: sourceLimits)

        var metadata: [FrameMetadata] = []
        metadata.reserveCapacity(frameCount)
        var sourceDurations: [Double] = []
        sourceDurations.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            try Task.checkCancellation()
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [String: Any],
                let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
                let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
                throw Failure.invalidFrameDimensions(index: index)
            }
            metadata.append(
                FrameMetadata(pixelWidth: width.intValue, pixelHeight: height.intValue)
            )
            sourceDurations.append(frameDuration(properties: properties))
        }

        // Source dimensions and frame count still bound ImageIO's work; the aggregate
        // pixel budget applies to the thumbnails we retain for playback.
        try validate(encodedByteCount: data.count, frames: metadata, limits: sourceLimits)
        let canvasPixels = canvasWidth.intValue * canvasHeight.intValue
        let largestFramePixels = metadata.map { $0.pixelWidth * $0.pixelHeight }.max() ?? canvasPixels
        // Retained frames are composed canvases even if source metadata describes a subrect.
        let (selectedPixels, pixelOverflow) = max(canvasPixels, largestFramePixels)
            .multipliedReportingOverflow(by: groups.count)
        guard !pixelOverflow else { throw Failure.totalPixelCountOverflow(index: groups.count - 1) }
        let thumbnailDimension: Int?
        if selectedPixels > limits.maximumTotalDecodedPixels {
            let pixelsPerFrame = limits.maximumTotalDecodedPixels / groups.count
            guard pixelsPerFrame > 0 else {
                throw Failure.totalPixelsExceeded(
                    atFrame: 0,
                    actual: groups.count,
                    limit: limits.maximumTotalDecodedPixels
                )
            }
            // A square bound also contains narrow frames and avoids rounding over budget.
            thumbnailDimension = Int(Double(pixelsPerFrame).squareRoot().rounded(.down))
        } else {
            thumbnailDimension = nil
        }

        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        var frames: [UIImage] = []
        frames.reserveCapacity(groups.count)
        var decodedMetadata: [FrameMetadata] = []
        decodedMetadata.reserveCapacity(groups.count)
        var frameDurations: [Double] = []
        frameDurations.reserveCapacity(groups.count)
        for group in groups {
            try Task.checkCancellation()
            // Preserve long-held poses instead of extending a brief transition over the group.
            var index = group.lowerBound
            for candidate in group.dropFirst() where sourceDurations[candidate] > sourceDurations[index] {
                index = candidate
            }
            // ImageIO composes preceding disposal/transparency before returning this source index.
            let decodedFrame: CGImage?
            if let thumbnailDimension {
                decodedFrame = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: thumbnailDimension,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
            } else {
                decodedFrame = CGImageSourceCreateImageAtIndex(source, index, decodeOptions)
            }
            guard let cgImage = decodedFrame else {
                throw Failure.frameDecodeFailed(index: index)
            }
            try Task.checkCancellation()
            decodedMetadata.append(.init(pixelWidth: cgImage.width, pixelHeight: cgImage.height))
            try validate(encodedByteCount: data.count, frames: decodedMetadata, limits: limits)
            frames.append(UIImage(cgImage: cgImage))
            frameDurations.append(sourceDurations[group].reduce(0, +))
        }

        guard let firstFrame = frames.first else { throw Failure.imageAssemblyFailed }
        if frames.count == 1 {
            return DecodedImage(image: firstFrame)
        }
        let playbackFrames = playbackFrameIndices(
            durations: frameDurations,
            maximumFrameCount: limits.maximumPlaybackFrameCount
        ).map { frames[$0] }
        let totalDuration = frameDurations.reduce(0, +)
        guard let animatedImage = UIImage.animatedImage(
            with: playbackFrames,
            duration: totalDuration
        ) else {
            throw Failure.imageAssemblyFailed
        }
        return DecodedImage(image: animatedImage)
    }

    static func frameGroups(sourceFrameCount: Int, maximumFrameCount: Int) -> [Range<Int>] {
        guard (1...maximumSourceFrameCount).contains(sourceFrameCount), maximumFrameCount > 0 else {
            return []
        }
        let retainedCount = min(sourceFrameCount, maximumFrameCount)
        return (0..<retainedCount).map { index in
            (index * sourceFrameCount / retainedCount)..<((index + 1) * sourceFrameCount / retainedCount)
        }
    }

    private static func frameDuration(properties: [String: Any]) -> Double {
        guard let gifProperties = properties[kCGImagePropertyGIFDictionary as String]
                as? [String: Any] else {
            return 0.1
        }

        let clampedDelay = (gifProperties[kCGImagePropertyGIFDelayTime as String]
            as? NSNumber)?.doubleValue
        let unclampedDelay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String]
            as? NSNumber)?.doubleValue
        return playbackDuration(clamped: clampedDelay, unclamped: unclampedDelay)
    }

    static func playbackDuration(clamped: Double?, unclamped: Double?) -> Double {
        let duration = clamped ?? unclamped ?? 0.1
        guard duration.isFinite, duration >= 0.02 else { return 0.1 }
        return min(duration, 60)
    }

    static func playbackFrameIndices(
        durations: [Double],
        maximumFrameCount: Int
    ) -> [Int] {
        guard !durations.isEmpty, maximumFrameCount >= durations.count else {
            return Array(durations.indices)
        }

        let maximumTicks = maximumFrameCount * 1_000
        let durationTicks = durations.map { duration in
            min(max(Int((duration * 1_000).rounded()), 1), maximumTicks)
        }
        let commonTick = durationTicks.dropFirst().reduce(durationTicks[0], greatestCommonDivisor)
        var repeats = durationTicks.map { $0 / commonTick }

        if repeats.reduce(0, +) > maximumFrameCount {
            repeats = proportionalRepeats(
                durationTicks: durationTicks,
                maximumFrameCount: maximumFrameCount
            )
        }

        return zip(durations.indices, repeats).flatMap { index, repeatCount in
            Array(repeating: index, count: repeatCount)
        }
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }

    private static func proportionalRepeats(
        durationTicks: [Int],
        maximumFrameCount: Int
    ) -> [Int] {
        var repeats = Array(repeating: 0, count: durationTicks.count)
        var activeIndices = Array(durationTicks.indices)
        var remainingSlots = maximumFrameCount

        while !activeIndices.isEmpty {
            let activeTicks = activeIndices.reduce(0) { $0 + durationTicks[$1] }
            let minimumShareIndices = activeIndices.filter { index in
                Double(remainingSlots) * Double(durationTicks[index]) / Double(activeTicks) < 1
            }
            guard !minimumShareIndices.isEmpty else { break }

            for index in minimumShareIndices {
                repeats[index] = 1
                remainingSlots -= 1
            }
            let minimumShareSet = Set(minimumShareIndices)
            activeIndices.removeAll { minimumShareSet.contains($0) }
        }

        guard !activeIndices.isEmpty else { return repeats }

        let activeTicks = activeIndices.reduce(0) { $0 + durationTicks[$1] }
        var fractions: [(index: Int, fraction: Double)] = []
        var assignedSlots = 0

        for index in activeIndices {
            let exactShare = Double(remainingSlots) * Double(durationTicks[index])
                / Double(activeTicks)
            let wholeShare = Int(exactShare.rounded(.down))
            repeats[index] = wholeShare
            assignedSlots += wholeShare
            fractions.append((index, exactShare - Double(wholeShare)))
        }

        fractions.sort { $0.fraction > $1.fraction }
        for item in fractions.prefix(remainingSlots - assignedSlots) {
            repeats[item.index] += 1
        }
        return repeats
    }
}

nonisolated enum GIFImageLoader {
    enum Failure: Error, Equatable {
        case tooLarge
        case failed
    }

    static func load(
        from url: URL,
        limits: GIFDecoder.Limits = .default,
        limiter: GIFLoadLimiter = .shared
    ) async throws -> GIFDecoder.DecodedImage {
        do {
            return try await load(limits: limits, limiter: limiter) {
                try await BoundedImageDataLoader.data(
                    from: url,
                    maximumBytes: limits.maximumEncodedBytes
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as BoundedImageDataLoader.Failure {
            switch failure {
            case .encodedDataTooLarge:
                throw Failure.tooLarge
            case .invalidMaximumBytes, .httpStatus, .emptyResponse:
                throw Failure.failed
            }
        } catch let failure as GIFDecoder.Failure {
            throw failure.isResourceLimit ? Failure.tooLarge : Failure.failed
        } catch {
            throw Failure.failed
        }
    }

    static func load(
        limits: GIFDecoder.Limits,
        limiter: GIFLoadLimiter,
        download: @Sendable () async throws -> Data
    ) async throws -> GIFDecoder.DecodedImage {
        let data = try await download()
        return try await limiter.withPermit {
            try await decode(data: data, limits: limits)
        }
    }

    static func load(
        data: Data,
        limits: GIFDecoder.Limits = .default,
        limiter: GIFLoadLimiter = .shared
    ) async throws -> GIFDecoder.DecodedImage {
        do {
            return try await limiter.withPermit {
                try await decode(data: data, limits: limits)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as GIFDecoder.Failure {
            throw failure.isResourceLimit ? Failure.tooLarge : Failure.failed
        } catch {
            throw Failure.failed
        }
    }

    private static func decode(
        data: Data,
        limits: GIFDecoder.Limits
    ) async throws -> GIFDecoder.DecodedImage {
        try Task.checkCancellation()
        let decodeTask = Task.detached(priority: .userInitiated) {
            try GIFDecoder.image(from: data, limits: limits)
        }
        return try await withTaskCancellationHandler {
            try await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }
}
