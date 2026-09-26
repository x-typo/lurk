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
        let hide = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            await gate.wait()
            log.events.append("hide")
        }, onFailure: log.unexpected)
        let undo = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            log.events.append("unhide")
        }, onFailure: log.unexpected)
        let rehide = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            log.events.append("hide again")
        }, onFailure: log.unexpected)

        await gate.waitUntilStarted()
        #expect(log.events.isEmpty)
        gate.open()
        await hide.value
        await undo.value
        await rehide.value
        #expect(log.events == ["hide", "unhide", "hide again"])
    }

    @Test("A failure is reported only while it's still the post's latest action")
    func staleFailureIsIgnored() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            await gate.wait()
            throw URLError(.badServerResponse)
        }, onFailure: { _ in log.events.append("hide failed") })
        let undo = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            log.events.append("unhide")
        }, onFailure: { _ in log.events.append("unhide failed") })

        await gate.waitUntilStarted()
        gate.open()
        await hide.value
        await undo.value
        #expect(log.events == ["unhide"])

        let lone = sync.enqueue(postID: "b", account: "x", currentAccount: { log.account }, send: {
            throw URLError(.timedOut)
        }, onFailure: { _ in log.events.append("b failed") })
        await lone.value
        #expect(log.events == ["unhide", "b failed"])
    }

    @Test("A queued write is dropped if the account changed before it could be sent")
    func dropsWritesAfterAccountChange() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let hide = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            await gate.wait()
            log.events.append("hide")
        }, onFailure: log.unexpected)
        let undo = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            log.events.append("unhide as the wrong account")
        }, onFailure: log.unexpected)

        await gate.waitUntilStarted()
        log.account = "y"
        gate.open()
        await hide.value
        await undo.value
        #expect(log.events == ["hide"])

        log.account = nil
        let signedOut = sync.enqueue(postID: "c", account: "x", currentAccount: { log.account }, send: {
            log.events.append("sent while signed out")
        }, onFailure: log.unexpected)
        await signedOut.value
        #expect(log.events == ["hide"])
    }

    @Test("Different posts don't wait on each other, and a finished post starts fresh")
    func postsAreIndependent() async {
        let sync = PostHideSync()
        let gate = Gate()
        let log = Log()
        let slow = sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            await gate.wait()
            log.events.append("a")
        }, onFailure: log.unexpected)
        await gate.waitUntilStarted()

        await sync.enqueue(postID: "b", account: "x", currentAccount: { log.account }, send: {
            log.events.append("b")
        }, onFailure: log.unexpected).value
        #expect(log.events == ["b"])

        gate.open()
        await slow.value
        await sync.enqueue(postID: "a", account: "x", currentAccount: { log.account }, send: {
            log.events.append("a again")
        }, onFailure: log.unexpected).value
        #expect(log.events == ["b", "a", "a again"])
    }

    @MainActor
    private final class Log {
        var events: [String] = []
        var account: String? = "x"

        func unexpected(_ error: Error) {
            Issue.record("Unexpected failure: \(error)")
        }
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
