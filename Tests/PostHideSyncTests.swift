import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Post hide sync")
struct PostHideSyncTests {
    @Test("A post's writes reach Reddit in the order they were made")
    func ordersWritesPerPost() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) {
            await gate.wait()
            log.events.append("hide")
        }
        let undo = enqueue(sync, log, hidden: false) { log.events.append("unhide") }
        let rehide = enqueue(sync, log, hidden: true) { log.events.append("hide again") }

        await gate.waitUntilStarted()
        #expect(log.events.isEmpty)
        gate.open()
        await hide.value
        await undo.value
        await rehide.value
        #expect(log.events == ["hide", "unhide", "hide again"])
        #expect(log.failures.isEmpty)
    }

    @Test("A superseded failure is ignored; a failed latest write rolls back")
    func staleFailureIsIgnored() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) {
            await gate.wait()
            throw URLError(.badServerResponse)
        }
        let undo = enqueue(sync, log, hidden: false) { log.events.append("unhide") }

        await gate.waitUntilStarted()
        gate.open()
        await hide.value
        await undo.value
        #expect(log.events == ["unhide"])
        #expect(log.failures.isEmpty)

        await enqueue(sync, log, postID: "b", hidden: true) { throw URLError(.timedOut) }.value
        #expect(log.failures == ["b hidden=true"])
    }

    @Test("When the hide and its Undo both fail, the post stays visible")
    func noRollbackWhenRedditNeverChanged() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) {
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        }
        let undo = enqueue(sync, log, hidden: false) { throw URLError(.notConnectedToInternet) }

        await gate.waitUntilStarted()
        gate.open()
        await hide.value
        await undo.value
        #expect(log.failures.isEmpty)
    }

    @Test("When the hide succeeds but its Undo fails, the post goes back to hidden")
    func rollbackWhenRedditKeptTheHide() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) { await gate.wait() }
        let undo = enqueue(sync, log, hidden: false) { throw URLError(.timedOut) }

        await gate.waitUntilStarted()
        gate.open()
        await hide.value
        await undo.value
        #expect(log.failures == ["a hidden=false"])
    }

    @Test("A queued write is dropped if the account changed before it could be sent")
    func dropsWritesAfterAccountChange() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) {
            await gate.wait()
            log.events.append("hide")
        }
        let undo = enqueue(sync, log, hidden: false) { log.events.append("unhide as the wrong account") }

        await gate.waitUntilStarted()
        log.account = "y"
        gate.open()
        await hide.value
        await undo.value
        #expect(log.events == ["hide"])

        log.account = nil
        await enqueue(sync, log, postID: "c", hidden: true) { log.events.append("sent while signed out") }.value
        #expect(log.events == ["hide"])
        #expect(log.failures.isEmpty)
    }

    @Test("A failure after sign-out, or after a newer local-only action, is ignored")
    func ignoresFailuresAfterSignOut() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = enqueue(sync, log, hidden: true) {
            await gate.wait()
            throw URLError(.timedOut)
        }
        await gate.waitUntilStarted()
        log.account = nil
        gate.open()
        await hide.value
        #expect(log.failures.isEmpty)

        log.account = "x"
        let secondGate = Gate()
        let second = enqueue(sync, log, postID: "d", hidden: true) {
            await secondGate.wait()
            throw URLError(.timedOut)
        }
        await secondGate.waitUntilStarted()
        sync.supersede(postID: "d")
        secondGate.open()
        await second.value
        #expect(log.failures.isEmpty)
    }

    @Test("Different posts don't wait on each other, and a finished post starts fresh")
    func postsAreIndependent() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let slow = enqueue(sync, log, hidden: true) {
            await gate.wait()
            log.events.append("a")
        }
        await gate.waitUntilStarted()

        await enqueue(sync, log, postID: "b", hidden: true) { log.events.append("b") }.value
        #expect(log.events == ["b"])

        gate.open()
        await slow.value
        await enqueue(sync, log, hidden: false) { log.events.append("a again") }.value
        #expect(log.events == ["b", "a", "a again"])
        #expect(log.failures.isEmpty)
    }

    @discardableResult
    private func enqueue(
        _ sync: PostHideSync,
        _ log: Log,
        postID: String = "a",
        hidden: Bool,
        send: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        sync.enqueue(
            postID: postID,
            hidden: hidden,
            account: "x",
            currentAccount: { log.account },
            send: send,
            onFailure: { _ in log.failures.append("\(postID) hidden=\(hidden)") }
        )
    }

    @MainActor
    private final class Log {
        var events: [String] = []
        var failures: [String] = []
        var account: String? = "x"
    }
}
