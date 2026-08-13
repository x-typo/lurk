import Foundation
import Testing
@testable import Lurk

@Suite("GIF download validation")
struct MediaSaverTests {
    @Test("GIF downloads require a successful HTTP response within the encoded-byte budget")
    func acceptsSuccessfulDownloadWithinLimit() throws {
        let response = try #require(httpResponse(statusCode: 200))

        #expect(MediaSaver.isValidGIFDownload(
            response: response,
            fileSize: GIFDecoder.Limits.default.maximumEncodedBytes,
            signature: Data("GIF89a".utf8)
        ))
    }

    @Test("GIF downloads reject non-2xx responses and files over the encoded-byte budget")
    func rejectsInvalidDownloads() throws {
        let badResponse = try #require(httpResponse(statusCode: 404))
        let successResponse = try #require(httpResponse(statusCode: 204))
        let limit = GIFDecoder.Limits.default.maximumEncodedBytes

        #expect(!MediaSaver.isValidGIFDownload(
            response: badResponse,
            fileSize: 6,
            signature: Data("GIF89a".utf8)
        ))
        #expect(!MediaSaver.isValidGIFDownload(
            response: successResponse,
            fileSize: limit + 1,
            signature: Data("GIF89a".utf8)
        ))
        #expect(!MediaSaver.isValidGIFDownload(
            response: successResponse,
            fileSize: 6,
            signature: Data("notgif".utf8)
        ))
        #expect(!MediaSaver.isValidGIFDownload(
            response: successResponse,
            fileSize: 0,
            signature: Data("GIF89a".utf8)
        ))
    }

    @Test("Streaming GIF download stops at the byte budget and removes the partial file")
    @MainActor
    func stopsStreamingAtByteBudget() async throws {
        let response = try #require(httpResponse(statusCode: 200))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let payload = Data("GIF89a-over-budget".utf8)
        let bytes = AsyncStream<UInt8> { continuation in
            payload.forEach { continuation.yield($0) }
            continuation.finish()
        }

        do {
            try await MediaSaver.writeGIFDownload(
                bytes: bytes,
                response: response,
                to: outputURL,
                maximumEncodedBytes: 8
            )
            Issue.record("Expected the streaming writer to reject the ninth byte")
        } catch {
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test("Streaming GIF download writes a valid response without exceeding its budget")
    @MainActor
    func writesValidStreamWithinBudget() async throws {
        let response = try #require(httpResponse(statusCode: 200))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var payload = Data("GIF89a".utf8)
        payload.append(Data(repeating: 0x47, count: 64 * 1_024 + 17))
        let bytes = AsyncStream<UInt8> { continuation in
            payload.forEach { continuation.yield($0) }
            continuation.finish()
        }

        try await MediaSaver.writeGIFDownload(
            bytes: bytes,
            response: response,
            to: outputURL,
            maximumEncodedBytes: payload.count
        )

        #expect(try Data(contentsOf: outputURL) == payload)
    }

    @Test("Cancelling a streaming GIF download removes its partial file")
    func removesPartialFileAfterCancellation() async throws {
        let response = try #require(httpResponse(statusCode: 200))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
        Data(repeating: 0x47, count: 64 * 1_024).forEach {
            continuation.yield($0)
        }

        let downloadTask = Task {
            do {
                try await MediaSaver.writeGIFDownload(
                    bytes: bytes,
                    response: response,
                    to: outputURL,
                    maximumEncodedBytes: 128 * 1_024
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        var partialFileExists = false
        for _ in 0..<100 {
            partialFileExists = FileManager.default.fileExists(atPath: outputURL.path)
            if partialFileExists { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(partialFileExists)

        downloadTask.cancel()
        continuation.finish()

        #expect(await downloadTask.value)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test("Cancelling a video fallback stops before the next URL")
    func cancellationStopsVideoFallback() async throws {
        let firstURL = URL(string: "https://example.com/first.mp4")!
        let secondURL = URL(string: "https://example.com/second.mp4")!
        let attempts = VideoAttemptProbe()
        let gate = CancellationGate()

        let task = Task {
            try await MediaSaver.firstTemporaryVideoFile(
                from: [firstURL, secondURL]
            ) { url in
                await attempts.record(url)
                await gate.waitUntilOpen()
                try Task.checkCancellation()
                throw FixtureFailure.expected
            }
        }

        #expect(await waitForAttemptCount(attempts, count: 1))
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            Issue.record("Expected video fallback cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await attempts.recordedURLs() == [firstURL])
    }

    @Test("Failed video export cleanup removes partial output")
    func removesPartialVideoExport() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("partial video".utf8).write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            _ = try await MediaSaver.keepTemporaryFileOnSuccess(at: outputURL) {
                throw FixtureFailure.expected
            }
            Issue.record("Expected video export failure")
        } catch FixtureFailure.expected {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse? {
        HTTPURLResponse(
            url: URL(string: "https://example.com/image.gif")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    }

    private func waitForAttemptCount(
        _ probe: VideoAttemptProbe,
        count: Int
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await probe.recordedURLs().count == count {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private enum FixtureFailure: Error {
        case expected
    }

    private actor VideoAttemptProbe {
        private var urls: [URL] = []

        func record(_ url: URL) {
            urls.append(url)
        }

        func recordedURLs() -> [URL] {
            urls
        }
    }

    private actor CancellationGate {
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
}
