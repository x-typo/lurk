import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Unread comment reply indicator")
struct UnreadRepliesStoreTests {
    @Test("Bounded empty pages and errors preserve unread; an exhausted scan clears it")
    func boundedRefresh() async throws {
        let store = UnreadRepliesStore()
        await store.refresh(account: "one") { _, _ in try listing(["first"]) }
        #expect(store.hasUnread)
        var calls = 0
        await store.refresh(account: "one") { filter, _ in
            #expect(filter == .unread)
            calls += 1
            return try listing([], after: "page\(calls)")
        }
        #expect(calls == 5 && store.hasUnread)
        store.didMarkRead("t1_first", account: "one", accountGeneration: store.accountGeneration)
        #expect(store.hasUnread)
        await store.refresh(account: "one") { _, _ in throw URLError(.timedOut) }
        #expect(store.hasUnread)
        await store.refresh(account: "one") { _, _ in try listing([]) }
        #expect(!store.hasUnread)
    }

    @Test("An unknown scan does not invent unread; later filtered pages can establish it")
    func findReplyAfterEmptyPage() async throws {
        let store = UnreadRepliesStore()
        await store.refresh(account: "one") { _, _ in throw URLError(.timedOut) }
        #expect(!store.hasUnread)
        await store.refresh(account: "one") { _, cursor in
            try listing(cursor == nil ? [] : ["found"], after: cursor == nil ? "next" : nil)
        }
        #expect(store.hasUnread)
    }

    @Test("Account changes and logout reject old scans and old account reads")
    func accountIsolation() async throws {
        let store = UnreadRepliesStore()
        let gate = Gate()
        let old = Task {
            await store.refresh(account: "one") { _, _ in
                await gate.wait()
                return try listing(["old"])
            }
        }
        await gate.waitUntilStarted()
        let oldAccountGeneration = store.accountGeneration
        await store.refresh(account: "two") { _, _ in try listing(["new"]) }
        store.didMarkRead("t1_new", account: "one", accountGeneration: oldAccountGeneration)
        #expect(store.hasUnread)
        store.setAccount(nil)
        gate.open()
        await old.value
        #expect(!store.hasUnread && store.account == nil)
        await store.refresh(account: nil) { _, _ in
            Issue.record("Logged out refresh must not request inbox data")
            return try listing([])
        }
    }

    @Test("Successful reads invalidate overlapping snapshots; later fresh server data reconciles")
    func readSynchronization() async throws {
        let store = UnreadRepliesStore()
        await store.refresh(account: "one") { _, _ in try listing(["first", "second"]) }
        let gate = Gate()
        let old = Task {
            await store.refresh(account: "one") { _, _ in
                await gate.wait()
                return try listing(["first", "second"])
            }
        }
        await gate.waitUntilStarted()
        store.didMarkRead("t1_first", account: "one", accountGeneration: store.accountGeneration)
        #expect(store.hasUnread)
        store.didMarkRead("t1_second", account: "one", accountGeneration: store.accountGeneration)
        #expect(!store.hasUnread)
        gate.open()
        await old.value
        #expect(!store.hasUnread)
        await store.refresh(account: "one") { _, _ in try listing(["first"]) }
        #expect(store.hasUnread)
    }

    @Test("A newer refresh wins and same-name re-login rejects the old account write")
    func newerRefreshAndRelogin() async throws {
        let store = UnreadRepliesStore()
        let gate = Gate()
        let old = Task {
            await store.refresh(account: "one") { _, _ in
                await gate.wait()
                return try listing(["old"])
            }
        }
        await gate.waitUntilStarted()
        let oldAccountGeneration = store.accountGeneration
        await store.refresh(account: "one") { _, _ in try listing([]) }
        gate.open()
        await old.value
        #expect(!store.hasUnread)
        store.setAccount(nil)
        await store.refresh(account: "one") { _, _ in try listing(["same"]) }
        store.didMarkRead("t1_same", account: "one", accountGeneration: oldAccountGeneration)
        #expect(store.hasUnread)
    }

    @Test("Inbox reload and pagination discover unread without another badge request")
    func inboxDiscovery() async throws {
        let badge = UnreadRepliesStore()
        let inbox = InboxStore()
        badge.setAccount("one")
        var context = badge.snapshotContext
        await inbox.load(filter: .unread, account: "one") { _, _ in try listing(["new"]) }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(badge.hasUnread)
        context = badge.snapshotContext
        await inbox.load(filter: .unread, account: "one") { _, _ in try listing([]) }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(!badge.hasUnread)

        var pages = 0
        context = badge.snapshotContext
        await inbox.load(filter: .unread, account: "one") { _, _ in
            pages += 1
            return try listing([], after: "page\(pages)")
        }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(!badge.hasUnread)
        context = badge.snapshotContext
        await inbox.loadMore { _, _ in try listing(["later"]) }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(badge.hasUnread)
    }

    @Test("Partial All and failed Inbox snapshots cannot clear known unread")
    func inboxUncertainty() async throws {
        let badge = UnreadRepliesStore()
        let inbox = InboxStore()
        await badge.refresh(account: "one") { _, _ in try listing(["known"]) }
        var context = badge.snapshotContext
        var readListing = try listing(["read"], after: "more")
        var readReplies = readListing.data.replies
        readReplies[0].isUnread = false
        readListing = InboxListing(data: InboxListingData(after: "more", replies: readReplies))
        await inbox.load(filter: .all, account: "one") { _, _ in readListing }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(badge.hasUnread)
        context = badge.snapshotContext
        await inbox.loadMore { _, _ in throw URLError(.timedOut) }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(badge.hasUnread)
        context = badge.snapshotContext
        await inbox.load(filter: .all, account: "one") { _, _ in
            InboxListing(data: InboxListingData(after: nil, replies: readReplies))
        }
        badge.reconcile(inbox, account: "one", context: context)
        #expect(!badge.hasUnread)
    }

    @Test("Inbox snapshots started before a read or account switch cannot restore the indicator")
    func staleInboxSnapshot() async throws {
        let badge = UnreadRepliesStore()
        let inbox = InboxStore()
        await badge.refresh(account: "one") { _, _ in try listing(["known"]) }
        let beforeRead = badge.snapshotContext
        await inbox.load(filter: .unread, account: "one") { _, _ in try listing(["known"]) }
        badge.didMarkRead("t1_known", account: "one", accountGeneration: badge.accountGeneration)
        badge.reconcile(inbox, account: "one", context: beforeRead)
        #expect(!badge.hasUnread)
        let beforeSwitch = badge.snapshotContext
        badge.setAccount(nil)
        badge.setAccount("one")
        badge.reconcile(inbox, account: "one", context: beforeSwitch)
        #expect(!badge.hasUnread)
    }

    @Test("An older Inbox snapshot cannot replace or invalidate a newer refresh")
    func newerRefreshWinsOverInbox() async throws {
        for finishRefreshFirst in [true, false] {
            let badge = UnreadRepliesStore()
            let inbox = InboxStore()
            badge.setAccount("one")
            let context = badge.snapshotContext
            let inboxGate = Gate()
            let oldInbox = Task {
                await inbox.load(filter: .unread, account: "one") { _, _ in
                    await inboxGate.wait()
                    return try listing([])
                }
                badge.reconcile(inbox, account: "one", context: context)
            }
            await inboxGate.waitUntilStarted()
            let refreshGate = Gate()
            let refresh = Task {
                await badge.refresh(account: "one") { _, _ in
                    await refreshGate.wait()
                    return try listing(["new"])
                }
            }
            await refreshGate.waitUntilStarted()
            if finishRefreshFirst {
                refreshGate.open()
                await refresh.value
            }
            inboxGate.open()
            await oldInbox.value
            if !finishRefreshFirst {
                refreshGate.open()
                await refresh.value
            }
            #expect(badge.hasUnread)
        }
    }

    private func listing(_ ids: [String], after: String? = nil) throws -> InboxListing {
        let children = ids.map { id in
            ["kind": "t1", "data": ["id": id, "body": "reply", "created_utc": 1,
                                       "subreddit": "swift", "new": true]] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "data": ["children": children, "after": after as Any? ?? NSNull()]
        ])
        return try RedditAPI.decoder.decode(InboxListing.self, from: data)
    }

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
