import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment loading")
struct CommentLoadStoreTests {
    @Test("Failure is explicit and retry publishes comments")
    func retriesFailure() async {
        let store = CommentLoadStore()
        await store.load { throw URLError(.notConnectedToInternet) }
        guard case .failed(let message) = store.state else {
            Issue.record("Expected an explicit failure")
            return
        }
        #expect(!message.isEmpty)
        #expect(store.comments.isEmpty)
        await store.load { [comment("recovered")] }
        #expect(store.state == .loaded)
        #expect(store.comments.map(\.id) == ["recovered"])
    }

    @Test("Connection and timeout failures give readable retry guidance")
    func readableNetworkFailures() async {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost] {
            let store = CommentLoadStore()
            await store.load { throw URLError(code) }
            #expect(store.state == .failed("Check your internet connection and try again."))
        }
        let store = CommentLoadStore()
        await store.load { throw URLError(.timedOut) }
        #expect(store.state == .failed("Loading comments took too long. Please try again."))
    }

    @Test("Unexpected failures retain their localized explanation")
    func unexpectedFailureFallback() async {
        let error = NSError(domain: "CommentTest", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected comment failure."])
        let store = CommentLoadStore()
        await store.load { throw error }
        #expect(store.state == .failed(error.localizedDescription))
    }

    @Test("Empty success is loaded and reappearance does not fetch again")
    func emptySuccess() async {
        let store = CommentLoadStore()
        await store.load { [] }
        #expect(store.state == .loaded)
        #expect(store.comments.isEmpty)
        store.cancel()
        await store.load {
            Issue.record("Loaded comments should be retained on reappearance")
            return []
        }
    }

    @Test("Top-level comment cap remains 30 and retains replies")
    func capsComments() async {
        let store = CommentLoadStore()
        let reply = comment("reply")
        await store.load { (0..<40).map { comment("\($0)", replies: [reply]) } }
        #expect(store.comments.count == 30)
        #expect(store.comments.last?.id == "29")
        #expect(store.comments.first?.replies.first?.id == "reply")
    }

    @Test("Loading is visible, overlapping loads coalesce, obsolete completion is ignored")
    func cancelsObsoleteFetch() async {
        let store = CommentLoadStore()
        let gate = Gate()
        let old = Task { await store.load { await gate.wait(); return [comment("old")] } }
        await gate.waitUntilStarted()
        #expect(store.state == .loading)
        await store.load {
            Issue.record("Concurrent request should have been coalesced")
            return []
        }
        store.cancel()
        #expect(store.state == .idle)
        await store.load { [comment("new")] }
        gate.open()
        await old.value
        #expect(store.state == .loaded)
        #expect(store.comments.map(\.id) == ["new"])
    }

    @Test("Task cancellation discards a late success and permits reappearance")
    func cancelledTaskCanRetry() async {
        let store = CommentLoadStore()
        let gate = Gate()
        let request = Task { await store.load { await gate.wait(); return [comment("cancelled")] } }
        await gate.waitUntilStarted()
        request.cancel()
        gate.open()
        await request.value
        #expect(store.state == .idle)
        #expect(store.comments.isEmpty)
        await store.load { [comment("new")] }
        #expect(store.comments.map(\.id) == ["new"])
    }

    @Test("Cancellation errors are recoverable without a misleading failure")
    func cancellationErrors() async {
        let store = CommentLoadStore()
        await store.load { throw CancellationError() }
        #expect(store.state == .idle)
        await store.load { throw URLError(.cancelled) }
        #expect(store.state == .idle)
        await store.load { [] }
        #expect(store.state == .loaded)
    }

    private func comment(_ id: String, replies: [Lurk.Comment] = []) -> Lurk.Comment {
        Lurk.Comment(id: id, author: "reader", body: "body", score: 1, createdUtc: 0,
                depth: 0, replies: replies, isSubmitter: false)
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var started: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started?.resume()
                started = nil
            }
        }

        func waitUntilStarted() async {
            guard continuation == nil else { return }
            await withCheckedContinuation { started = $0 }
        }

        func open() {
            continuation?.resume()
            continuation = nil
        }
    }
}
