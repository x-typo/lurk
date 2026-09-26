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
        #expect(store.nodes.isEmpty)
        await store.load { [comment("recovered")] }
        #expect(store.state == .loaded)
        #expect(ids(store) == ["recovered"])
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
        #expect(store.nodes.isEmpty)
        store.cancel()
        await store.load {
            Issue.record("Loaded comments should be retained on reappearance")
            return []
        }
    }

    @Test("Every top-level comment and reply is kept")
    func keepsAllComments() async {
        let store = CommentLoadStore()
        await store.load { (0..<40).map { comment("\($0)", replies: [comment("r\($0)", depth: 1)]) } }
        #expect(store.nodes.count == 40)
        #expect(ids(store).count == 80)
        #expect(ids(store).suffix(2) == ["39", "r39"])
    }

    @Test("Loaded replies replace their placeholder and skip comments already shown")
    func loadMoreSplices() async {
        let store = CommentLoadStore()
        let placeholder = CommentMore(parentID: "t1_a", depth: 1, count: 2, childIDs: ["b", "c"])
        await store.load { [comment("a", replies: [comment("b", depth: 1), .more(placeholder)])] }
        await store.loadMore(placeholder) { more in
            #expect(more == placeholder)
            return [comment("b", depth: 1), comment("c", depth: 1)]
        }
        #expect(ids(store) == ["a", "b", "c"])
        #expect(store.loadingMoreID == nil)
        #expect(store.moreErrors.isEmpty)
    }

    @Test("A failed load keeps the placeholder with a message, and retry clears it")
    func loadMoreFailureAndRetry() async {
        let store = CommentLoadStore()
        let placeholder = CommentMore(parentID: "t3_post", depth: 0, count: 1, childIDs: ["b"])
        await store.load { [comment("a"), .more(placeholder)] }
        await store.loadMore(placeholder) { _ in throw URLError(.notConnectedToInternet) }
        #expect(ids(store) == ["a", placeholder.id])
        #expect(store.moreErrors[placeholder.id] == "Check your internet connection and try again.")
        #expect(store.loadingMoreID == nil)

        await store.loadMore(placeholder) { _ in [comment("b")] }
        #expect(ids(store) == ["a", "b"])
        #expect(store.moreErrors.isEmpty)
    }

    @Test("Cancelled loads leave the placeholder without an error")
    func loadMoreCancellation() async {
        let store = CommentLoadStore()
        let placeholder = CommentMore(parentID: "t3_post", depth: 0, count: 1, childIDs: ["b"])
        await store.load { [.more(placeholder)] }
        await store.loadMore(placeholder) { _ in throw CancellationError() }
        #expect(ids(store) == [placeholder.id])
        #expect(store.moreErrors.isEmpty)
    }

    @Test("Only one placeholder loads at a time, and none before comments load")
    func loadMoreIsExclusive() async {
        let store = CommentLoadStore()
        let first = CommentMore(parentID: "t3_post", depth: 0, count: 1, childIDs: ["x"])
        let second = CommentMore(parentID: "t1_a", depth: 1, count: 1, childIDs: ["y"])
        await store.loadMore(first) { _ in
            Issue.record("Placeholders should not load before comments")
            return []
        }

        await store.load { [comment("a", replies: [.more(second)]), .more(first)] }
        let gate = Gate()
        let request = Task { await store.loadMore(first) { _ in await gate.wait(); return [comment("x")] } }
        await gate.waitUntilStarted()
        #expect(store.loadingMoreID == first.id)
        await store.loadMore(second) { _ in
            Issue.record("An overlapping placeholder load should be ignored")
            return []
        }
        gate.open()
        await request.value
        #expect(store.loadingMoreID == nil)
        #expect(ids(store) == ["a", second.id, "x"])
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
        #expect(ids(store) == ["new"])
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
        #expect(store.nodes.isEmpty)
        await store.load { [comment("new")] }
        #expect(ids(store) == ["new"])
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

    private func comment(_ id: String, depth: Int = 0, replies: [CommentNode] = []) -> CommentNode {
        .comment(Lurk.Comment(id: id, author: "reader", body: "body", score: 1, createdUtc: 0,
                              depth: depth, isSubmitter: false), replies: replies)
    }

    private func ids(_ store: CommentLoadStore) -> [String] {
        CommentNode.rows(from: store.nodes, collapsed: []).map(\.id)
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
