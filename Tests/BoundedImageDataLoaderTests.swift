import Foundation
import Testing
@testable import Lurk

@Suite("Bounded image networking")
struct BoundedImageDataLoaderTests {
    @Test("A reusable session rejects non-positive byte limits")
    func reusableSessionRejectsInvalidMaximumBytes() async {
        let session = BoundedImageDataSession(configuration: configuration())
        defer { session.invalidate() }

        for maximumBytes in [0, -1] {
            do {
                _ = try await session.data(from: testURL(), maximumBytes: maximumBytes)
                Issue.record("Expected the reusable session to reject an invalid byte limit")
            } catch let failure as BoundedImageDataLoader.Failure {
                #expect(failure == .invalidMaximumBytes)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Chunked networking accepts an exact byte boundary")
    func acceptsExactBoundary() async throws {
        let url = testURL()
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 200, contentLength: 4, chunks: [Data([1, 2]), Data([3, 4])]),
            for: url
        )

        let data = try await BoundedImageDataLoader.data(
            from: url,
            maximumBytes: 4,
            configuration: configuration()
        )

        #expect(Array(data) == [1, 2, 3, 4])
    }

    @Test("Observed bytes enforce the cap when content length is absent")
    func rejectsObservedOverflow() async {
        let url = testURL()
        let cancellationProbe = TaskCancellationProbe()
        BoundedLoaderURLProtocol.register(
            .init(
                statusCode: 200,
                chunks: [Data([1, 2, 3, 4, 5]), Data([6])],
                deliveryDelayMilliseconds: 250
            ),
            for: url
        )
        let session = BoundedImageDataSession(
            configuration: configuration(),
            cancellationObserver: cancellationProbe.record
        )
        defer { session.invalidate() }

        await expectOversizeFailure(
            from: url,
            maximumBytes: 4,
            minimumActualBytes: 5,
            session: session
        )
        #expect(cancellationProbe.count(for: url) == 1)
    }

    @Test("Declared content length rejects an oversized body before receipt")
    func rejectsDeclaredOverflow() async {
        let url = testURL()
        let cancellationProbe = TaskCancellationProbe()
        BoundedLoaderURLProtocol.register(
            .init(
                statusCode: 200,
                contentLength: 5,
                chunks: [Data([1, 2, 3, 4, 5])],
                deliveryDelayMilliseconds: 250
            ),
            for: url
        )
        let session = BoundedImageDataSession(
            configuration: configuration(),
            cancellationObserver: cancellationProbe.record
        )
        defer { session.invalidate() }

        await expectOversizeFailure(
            from: url,
            maximumBytes: 4,
            minimumActualBytes: 5,
            session: session
        )
        #expect(cancellationProbe.count(for: url) == 1)
    }

    @Test("HTTP failures preserve their status code")
    func rejectsHTTPFailure() async {
        let url = testURL()
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 503, contentLength: 1, chunks: [Data([1])]),
            for: url
        )

        await expectFailure(.httpStatus(503), from: url, maximumBytes: 4)
    }

    @Test("A successful empty body is rejected")
    func rejectsEmptyResponse() async {
        let url = testURL()
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 200, contentLength: 0, chunks: []),
            for: url
        )

        await expectFailure(.emptyResponse, from: url, maximumBytes: 4)
    }

    @Test("Task cancellation stops the underlying URL load")
    func cancellationStopsTransfer() async {
        let url = testURL()
        let cancellationProbe = TaskCancellationProbe()
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 200, holdOpen: true, failureDelayMilliseconds: 1_000),
            for: url
        )
        let session = BoundedImageDataSession(
            configuration: configuration(),
            cancellationObserver: cancellationProbe.record
        )
        defer { session.invalidate() }

        let task = Task {
            try await session.data(from: url, maximumBytes: 4)
        }
        #expect(await waitForStart(url))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the transfer to be cancelled")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(cancellationProbe.count(for: url) == 1)
    }

    @Test("A reusable session keeps concurrent transfer state isolated")
    func reusableSessionIsolatesConcurrentTransfers() async throws {
        let acceptedURL = testURL()
        let rejectedURL = testURL()
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 200, contentLength: 4, chunks: [Data([1, 2, 3, 4])]),
            for: acceptedURL
        )
        BoundedLoaderURLProtocol.register(
            .init(statusCode: 200, chunks: [Data([1, 2, 3, 4, 5])]),
            for: rejectedURL
        )

        let session = BoundedImageDataSession(configuration: configuration())
        defer { session.invalidate() }
        async let accepted = session.data(from: acceptedURL, maximumBytes: 4)
        async let rejected = session.data(from: rejectedURL, maximumBytes: 4)

        #expect(Array(try await accepted) == [1, 2, 3, 4])
        do {
            _ = try await rejected
            Issue.record("Expected the oversized concurrent transfer to fail")
        } catch let failure as BoundedImageDataLoader.Failure {
            #expect(failure == .encodedDataTooLarge(actual: 5, limit: 4))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func expectFailure(
        _ expected: BoundedImageDataLoader.Failure,
        from url: URL,
        maximumBytes: Int
    ) async {
        do {
            _ = try await BoundedImageDataLoader.data(
                from: url,
                maximumBytes: maximumBytes,
                configuration: configuration()
            )
            Issue.record("Expected bounded networking to fail")
        } catch let failure as BoundedImageDataLoader.Failure {
            #expect(failure == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func expectOversizeFailure(
        from url: URL,
        maximumBytes: Int,
        minimumActualBytes: Int64,
        session: BoundedImageDataSession
    ) async {
        do {
            _ = try await session.data(from: url, maximumBytes: maximumBytes)
            Issue.record("Expected bounded networking to reject oversized data")
        } catch let failure as BoundedImageDataLoader.Failure {
            guard case .encodedDataTooLarge(let actual, let limit) = failure else {
                Issue.record("Unexpected bounded networking failure: \(failure)")
                return
            }
            #expect(actual >= minimumActualBytes)
            #expect(limit == maximumBytes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedLoaderURLProtocol.self]
        return configuration
    }

    private func testURL() -> URL {
        URL(string: "https://gif-loader.test/\(UUID().uuidString)")!
    }

    private func waitForStart(_ url: URL) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if BoundedLoaderURLProtocol.startCount(for: url) > 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

}

private nonisolated final class BoundedLoaderURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let contentLength: Int64?
        let chunks: [Data]
        let holdOpen: Bool
        let deliveryDelayMilliseconds: Int
        let failureDelayMilliseconds: Int?

        init(
            statusCode: Int,
            contentLength: Int64? = nil,
            chunks: [Data] = [],
            holdOpen: Bool = false,
            deliveryDelayMilliseconds: Int = 1,
            failureDelayMilliseconds: Int? = nil
        ) {
            self.statusCode = statusCode
            self.contentLength = contentLength
            self.chunks = chunks
            self.holdOpen = holdOpen
            self.deliveryDelayMilliseconds = deliveryDelayMilliseconds
            self.failureDelayMilliseconds = failureDelayMilliseconds
        }
    }

    private struct Record {
        let stub: Stub
        var startCount = 0
        var stopCount = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var records: [URL: Record] = [:]

    static func register(_ stub: Stub, for url: URL) {
        withLock { records[url] = Record(stub: stub) }
    }

    static func startCount(for url: URL) -> Int {
        withLock { records[url]?.startCount ?? 0 }
    }

    static func stopCount(for url: URL) -> Int {
        withLock { records[url]?.stopCount ?? 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "gif-loader.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.startedStub(for: url),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: stub.contentLength.map { ["Content-Length": String($0)] }
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if stub.holdOpen {
            scheduleFailureIfNeeded(stub: stub, url: url)
            return
        }
        deliver(stub: stub, url: url, chunkIndex: 0)
    }

    override func stopLoading() {
        guard let url = request.url else { return }
        Self.withLock {
            guard var record = Self.records[url] else { return }
            record.stopCount += 1
            Self.records[url] = record
        }
    }

    private static func startedStub(for url: URL) -> Stub? {
        withLock {
            guard var record = records[url] else { return nil }
            record.startCount += 1
            records[url] = record
            return record.stub
        }
    }

    private func deliver(stub: Stub, url: URL, chunkIndex: Int) {
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .milliseconds(stub.deliveryDelayMilliseconds)
        ) { [weak self] in
            guard let self, Self.stopCount(for: url) == 0 else { return }
            guard chunkIndex < stub.chunks.count else {
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }
            self.client?.urlProtocol(self, didLoad: stub.chunks[chunkIndex])
            self.deliver(stub: stub, url: url, chunkIndex: chunkIndex + 1)
        }
    }

    private func scheduleFailureIfNeeded(stub: Stub, url: URL) {
        guard let delay = stub.failureDelayMilliseconds else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delay)) {
            [weak self] in
            guard let self, Self.stopCount(for: url) == 0 else { return }
            self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        }
    }

    private static func withLock<Value>(_ operation: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private nonisolated final class TaskCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]

    func record(_ task: URLSessionTask) {
        guard let url = task.originalRequest?.url else { return }
        lock.lock()
        counts[url, default: 0] += 1
        lock.unlock()
    }

    func count(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[url, default: 0]
    }
}
