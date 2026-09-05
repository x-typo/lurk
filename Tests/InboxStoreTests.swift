import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Inbox loading and explicit read state")
struct InboxStoreTests {
    @Test("Initial failure is retryable; refresh preserves existing content and cursor")
    func refreshFailure() async throws {
        let store = InboxStore()
        #expect(!store.isLoading && !store.hasLoaded)
        await store.load(filter: .unread, account: "one") { _, _ in throw URLError(.timedOut) }
        #expect(store.error != nil && !store.hasLoaded && !store.isLoading)
        let first = try listing(["first"], after: "a")
        await store.load(filter: .unread, account: "one") { _, _ in first }
        #expect(store.hasLoaded && store.error == nil)
        await store.load(filter: .unread, account: "one") { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(store.replies.map(\.id) == ["t1_first"])
        #expect(store.after == "a" && store.error != nil && store.paginationError == nil)
        #expect(store.error == "Check your internet connection and try again.")
    }

    @Test("Pagination failure preserves content and retries the same cursor")
    func paginationRetryAndDeduplication() async throws {
        let store = InboxStore()
        let first = try listing(["first", "first"], after: "a")
        await store.load(filter: .all, account: "one") { _, _ in first }
        await store.loadMore { filter, cursor in
            #expect(filter == .all && cursor == "a")
            throw URLError(.timedOut)
        }
        #expect(store.replies.count == 1 && store.after == "a")
        #expect(store.error == nil && store.paginationError != nil && !store.isLoadingMore)
        let second = try listing(["first", "second", "second"])
        await store.loadMore { _, cursor in
            #expect(cursor == "a")
            return second
        }
        #expect(store.replies.map(\.id) == ["t1_first", "t1_second"])
        #expect(store.after == nil && store.paginationError == nil)
    }

    @Test("Five private-message pages retain continuation for a manual next fetch")
    func boundedEmptyPages() async throws {
        let store = InboxStore()
        var calls = 0
        await store.load(filter: .unread, account: "one") { _, cursor in
            #expect(cursor == (calls == 0 ? nil : "page\(calls)"))
            calls += 1
            return try listing([], after: "page\(calls)", privateMessage: true)
        }
        #expect(calls == 5 && store.hasLoaded && store.replies.isEmpty)
        #expect(store.after == "page5" && store.error == nil)
        await store.loadMore { _, cursor in
            #expect(cursor == "page5")
            return try listing(["found"])
        }
        #expect(store.replies.map(\.id) == ["t1_found"] && store.after == nil)
    }

    @Test("Duplicate pages are skipped until a new reply appears")
    func duplicateOnlyPages() async throws {
        let store = InboxStore()
        await store.load(filter: .all, account: "one") { _, _ in try listing(["first"], after: "a") }
        var cursors: [String?] = []
        await store.loadMore { _, cursor in
            cursors.append(cursor)
            return try listing(cursor == "a" ? ["first"] : ["first", "second"], after: cursor == "a" ? "b" : nil)
        }
        #expect(cursors == ["a", "b"])
        #expect(store.replies.map(\.id) == ["t1_first", "t1_second"])
    }

    @Test("Cursor cycles across fetches produce a recoverable pagination error")
    func repeatedCursor() async throws {
        let store = InboxStore()
        await store.load(filter: .all, account: "one") { _, _ in try listing(["first"], after: "a") }
        await store.loadMore { _, _ in try listing(["second"], after: "b") }
        await store.loadMore { _, cursor in
            #expect(cursor == "b")
            return try listing(["third"], after: "a")
        }
        #expect(store.paginationError != nil && store.after == "b")
        #expect(store.replies.map(\.id) == ["t1_first", "t1_second"])
        await store.loadMore { _, cursor in
            #expect(cursor == "b")
            return try listing(["third"])
        }
        #expect(store.paginationError == nil && store.replies.count == 3)
    }

    @Test("Refresh supersedes an in-flight pagination completion")
    func refreshReplacesPagination() async throws {
        let store = InboxStore()
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["first"], after: "a") }
        let gate = Gate()
        let old = Task {
            await store.loadMore { _, _ in
                await gate.wait()
                return try listing(["obsolete"], after: "old")
            }
        }
        await gate.waitUntilStarted()
        #expect(store.isLoadingMore)
        await store.loadMore { _, _ in
            Issue.record("Overlapping pagination must be ignored")
            return try listing([])
        }
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["fresh"]) }
        gate.open()
        await old.value
        #expect(store.replies.map(\.id) == ["t1_fresh"])
        #expect(store.after == nil && !store.isLoading && !store.isLoadingMore)
    }

    @Test("Filter and account changes discard stale loads")
    func staleContextLoad() async throws {
        for switchAccount in [false, true] {
            let store = InboxStore()
            let gate = Gate()
            let old = Task {
                await store.load(filter: .unread, account: "one") { _, _ in
                    await gate.wait()
                    return try listing(["old"])
                }
            }
            await gate.waitUntilStarted()
            await store.load(filter: switchAccount ? .unread : .all, account: switchAccount ? "two" : "one") { _, _ in
                try listing(["current"])
            }
            gate.open()
            await old.value
            #expect(store.replies.map(\.id) == ["t1_current"])
        }
    }

    @Test("Cancellation discards a late successful load and permits retry")
    func cancelledLoad() async throws {
        let store = InboxStore()
        let gate = Gate()
        let request = Task {
            await store.load(filter: .unread, account: "one") { _, _ in
                await gate.wait()
                return try listing(["cancelled"])
            }
        }
        await gate.waitUntilStarted()
        request.cancel()
        gate.open()
        await request.value
        #expect(store.replies.isEmpty && !store.hasLoaded && !store.isLoading && store.error == nil)
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["retry"]) }
        #expect(store.replies.map(\.id) == ["t1_retry"])
    }

    @Test("Read write failure preserves the reply; retry removes it only after success")
    func readFailureAndRetry() async throws {
        let store = InboxStore()
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["first"]) }
        let reply = try #require(store.replies.first)
        await store.markRead(reply) { throw URLError(.timedOut) }
        #expect(store.replies.first?.isUnread == true && store.writeError != nil)
        #expect(store.writeError == "Reddit took too long to respond. Please try again.")
        #expect(store.markingReadIDs.isEmpty)
        let gate = Gate()
        let write = Task { await store.markRead(reply) { await gate.wait() } }
        await gate.waitUntilStarted()
        #expect(store.markingReadIDs == [reply.id] && store.replies.count == 1)
        await store.markRead(reply) { Issue.record("Duplicate row writes must be ignored") }
        gate.open()
        await write.value
        #expect(store.replies.isEmpty && store.markingReadIDs.isEmpty && store.writeError == nil)
    }

    @Test("Overlapping responses preserve reads; later loads reconcile server unread state")
    func readOverlayAcrossRefreshAndFilter() async throws {
        let store = InboxStore()
        await store.load(filter: .all, account: "one") { _, _ in try listing(["first"]) }
        let reply = try #require(store.replies.first)
        let gate = Gate()
        let refresh = Task {
            await store.load(filter: .all, account: "one") { _, _ in
                await gate.wait()
                return try listing(["first"])
            }
        }
        await gate.waitUntilStarted()
        await store.markRead(reply) {}
        #expect(store.replies.count == 1 && store.replies.first?.isUnread == false)
        gate.open()
        await refresh.value
        #expect(store.replies.first?.isUnread == false)
        await store.load(filter: .all, account: "one") { _, _ in try listing(["first"]) }
        #expect(store.replies.first?.isUnread == true)
        await store.markRead(try #require(store.replies.first)) {}
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["first"]) }
        #expect(store.replies.first?.isUnread == true)
        await store.markRead(try #require(store.replies.first)) {}
        await store.load(filter: .unread, account: "two") { _, _ in try listing(["first"]) }
        #expect(store.replies.first?.isUnread == true)
    }

    @Test("A successful write after a filter switch updates the current filter")
    func readDuringFilterSwitch() async throws {
        let store = InboxStore()
        await store.load(filter: .unread, account: "one") { _, _ in try listing(["first"]) }
        let reply = try #require(store.replies.first)
        let gate = Gate()
        let write = Task { await store.markRead(reply) { await gate.wait() } }
        await gate.waitUntilStarted()
        await store.load(filter: .all, account: "one") { _, _ in try listing(["first"]) }
        gate.open()
        await write.value
        #expect(store.replies.count == 1 && store.replies.first?.isUnread == false)
    }

    @Test("An old account's write cannot mutate a new account or clear its pending write")
    func staleAccountWrite() async throws {
        for oldWriteFails in [false, true] {
            let store = InboxStore()
            await store.load(filter: .unread, account: "one") { _, _ in try listing(["same"]) }
            let reply = try #require(store.replies.first)
            let oldGate = Gate()
            let oldWrite = Task {
                await store.markRead(reply) {
                    await oldGate.wait()
                    if oldWriteFails { throw URLError(.timedOut) }
                }
            }
            await oldGate.waitUntilStarted()
            await store.load(filter: .unread, account: "two") { _, _ in try listing(["same"]) }
            let newGate = Gate()
            let newWrite = Task { await store.markRead(reply) { await newGate.wait() } }
            await newGate.waitUntilStarted()
            oldGate.open()
            await oldWrite.value
            #expect(store.replies.first?.isUnread == true && store.writeError == nil)
            #expect(store.markingReadIDs == [reply.id])
            newGate.open()
            await newWrite.value
            #expect(store.replies.isEmpty && store.markingReadIDs.isEmpty)
        }
    }

    private func listing(_ ids: [String], after: String? = nil, privateMessage: Bool = false) throws -> InboxListing {
        var children: [[String: Any]] = ids.map {
            ["kind": "t1", "data": ["id": $0, "body": "reply", "created_utc": 1,
                                        "subreddit": "swift", "new": true]]
        }
        if privateMessage {
            children.append(["kind": "t4", "data": ["id": "private", "body": "message",
                                                       "created_utc": 1, "subreddit": "swift"]])
        }
        let json: [String: Any] = ["data": ["children": children, "after": after as Any? ?? NSNull()]]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(InboxListing.self, from: JSONSerialization.data(withJSONObject: json))
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
