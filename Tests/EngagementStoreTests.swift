import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Engagement store")
struct EngagementStoreTests {
    @Test("Session choices override the loaded vote and saved state")
    func sessionChoicesOverrideLoadedState() async {
        let store = EngagementStore()
        let log = Log()
        #expect(store.vote(for: "t3_a", loaded: 1) == 1)

        await store.submitVote(0, for: "t3_a", loaded: 1, send: {}, onFailure: log.fail).value
        await store.submitSave(true, for: "t3_a", loaded: false, send: {}, onFailure: log.fail).value
        await store.submitSave(false, for: "t3_b", loaded: true, send: {}, onFailure: log.fail).value

        #expect(store.vote(for: "t3_a", loaded: 1) == 0)
        #expect(store.isSaved("t3_a", loaded: false))
        #expect(!store.isSaved("t3_b", loaded: true))
        #expect(store.vote(for: "t3_other", loaded: -1) == -1)
        #expect(log.failures == 0)
    }

    @Test("A thing's writes reach Reddit in the order they were made")
    func ordersWritesPerThing() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        let up = store.submitVote(1, for: "t3_a", loaded: 0, send: {
            await gate.wait()
            log.events.append("up")
        }, onFailure: log.fail)
        let clear = store.submitVote(0, for: "t3_a", loaded: 0, send: { log.events.append("clear") }, onFailure: log.fail)

        await gate.waitUntilStarted()
        #expect(log.events.isEmpty)
        gate.open()
        await up.value
        await clear.value
        #expect(log.events == ["up", "clear"])
    }

    @Test("A superseded failure is ignored; a failed latest write shows Reddit's value again")
    func rollsBackOnlyTheLatestFailure() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        let up = store.submitVote(1, for: "t3_a", loaded: 0, send: {
            await gate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        let down = store.submitVote(-1, for: "t3_a", loaded: 0, send: {}, onFailure: log.fail)

        await gate.waitUntilStarted()
        gate.open()
        await up.value
        await down.value
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
        #expect(log.failures == 0)

        await store.submitVote(1, for: "t3_a", loaded: 0, send: { throw URLError(.timedOut) }, onFailure: log.fail).value
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
        #expect(log.failures == 1)
    }

    @Test("When a vote and its undo both fail, the display stays at Reddit's state and the failure is reported")
    func noRollbackWhenRedditNeverChanged() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        let up = store.submitVote(1, for: "t3_a", loaded: 0, send: {
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        }, onFailure: log.fail)
        let clear = store.submitVote(0, for: "t3_a", loaded: 0, send: {
            throw URLError(.notConnectedToInternet)
        }, onFailure: log.fail)

        await gate.waitUntilStarted()
        gate.open()
        await up.value
        await clear.value
        #expect(store.vote(for: "t3_a", loaded: 0) == 0)
        #expect(log.failures == 1)
    }

    @Test("A failed save goes back to Reddit's state and reports the error")
    func failedSaveRollsBack() async {
        let store = EngagementStore()
        let log = Log()
        await store.submitSave(true, for: "t3_a", loaded: false, send: { throw URLError(.timedOut) }, onFailure: log.fail).value
        #expect(!store.isSaved("t3_a", loaded: false))
        #expect(log.failures == 1)
    }

    @Test("An account change clears choices and drops the old account's queued writes")
    func accountChangeClearsState() async {
        let store = EngagementStore()
        store.setAccount("first")
        let gate = Gate()
        let log = Log()
        let slow = store.submitVote(1, for: "t3_a", loaded: 0, send: {
            await gate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        let queued = store.submitVote(-1, for: "t3_a", loaded: 0, send: {
            log.events.append("sent as the wrong account")
        }, onFailure: log.fail)

        await gate.waitUntilStarted()
        store.setAccount("second")
        #expect(store.vote(for: "t3_a", loaded: 0) == 0)
        gate.open()
        await slow.value
        await queued.value
        #expect(log.events.isEmpty)
        #expect(log.failures == 0)
        #expect(store.vote(for: "t3_a", loaded: 0) == 0)
    }

    @Test("Work from before signing out and back in to the same account can't send or roll back")
    func sameAccountAgainRejectsOldWork() async {
        let store = EngagementStore()
        store.setAccount("reader")
        let gate = Gate()
        let queuedGate = Gate()
        let log = Log()
        // "a": the old write is its lane's latest, so only the account check stops its rollback.
        let oldLatest = store.submitVote(1, for: "t3_a", loaded: 0, send: {
            await gate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        // "b": an old write is still queued behind another.
        let oldFirst = store.submitVote(1, for: "t3_b", loaded: 0, send: { await queuedGate.wait() }, onFailure: log.fail)
        let oldQueued = store.submitVote(0, for: "t3_b", loaded: 0, send: {
            log.events.append("old queued write sent")
        }, onFailure: log.fail)

        await gate.waitUntilStarted()
        await queuedGate.waitUntilStarted()
        store.setAccount(nil)
        store.setAccount("reader")
        await store.submitVote(-1, for: "t3_a", loaded: 0, send: { log.events.append("new write") }, onFailure: log.fail).value
        gate.open()
        queuedGate.open()
        await oldLatest.value
        await oldFirst.value
        await oldQueued.value
        #expect(log.events == ["new write"])
        #expect(log.failures == 0)
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
    }

    @Test("Settling an Unsave waits for a Save queued meanwhile and reports the final choice")
    func settledSaveWaitsForQueuedWrites() async {
        let store = EngagementStore()
        let unsaveGate = Gate()
        let saveGate = Gate()
        let log = Log()
        store.submitSave(false, for: "t3_a", loaded: true, send: { await unsaveGate.wait() }, onFailure: log.fail)
        let settled = Task { await store.settledSave("t3_a", loaded: true) }
        await unsaveGate.waitUntilStarted()
        store.submitSave(true, for: "t3_a", loaded: true, send: {
            await saveGate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)

        unsaveGate.open()
        await saveGate.waitUntilStarted()
        saveGate.open()
        #expect(await settled.value == false)
        #expect(log.failures == 1)
    }

    @Test("Waiting for an Unsave reports whether Reddit accepted that write, even after an ambiguous Save")
    func submitSaveAndWaitReportsThisWrite() async {
        let store = EngagementStore()
        let saveGate = Gate()
        let log = Log()
        #expect(await store.submitSaveAndWait(false, for: "t3_a", loaded: true, send: {}, onFailure: log.fail))

        // A Save that Reddit applied but whose response timed out, then an Unsave that fails offline.
        let save = store.submitSave(true, for: "t3_a", loaded: true, send: {
            await saveGate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        await saveGate.waitUntilStarted()
        let unsave = Task {
            await store.submitSaveAndWait(false, for: "t3_a", loaded: true, send: {
                throw URLError(.notConnectedToInternet)
            }, onFailure: log.fail)
        }
        saveGate.open()
        await save.value
        #expect(await unsave.value == false)
        #expect(log.failures == 1)
    }

    @Test("When an Unsave and a later Save both fail, the post settles as saved and the failure is reported")
    func bothFailSettlesSaved() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        store.submitSave(false, for: "t3_a", loaded: true, send: {
            await gate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        store.submitSave(true, for: "t3_a", loaded: true, send: { throw URLError(.timedOut) }, onFailure: log.fail)

        await gate.waitUntilStarted()
        gate.open()
        #expect(await store.settledSave("t3_a", loaded: true))
        #expect(log.failures == 1)
    }

    @Test("Only a fetch that started after a thing's writes settled replaces the session choice")
    func laterFetchReconciles() async {
        let store = EngagementStore()
        let log = Log()
        await store.submitVote(1, for: "t3_a", loaded: 0, send: {}, onFailure: log.fail).value
        await store.submitSave(true, for: "t3_a", loaded: false, send: {}, onFailure: log.fail).value

        store.reconcile(fetchStartedAt: .distantPast, votes: [("t3_a", 0)], saves: [("t3_a", false)])
        #expect(store.vote(for: "t3_a", loaded: 0) == 1)
        #expect(store.isSaved("t3_a", loaded: false))

        store.reconcile(fetchStartedAt: .now, votes: [("t3_a", -1), ("t3_b", 1)], saves: [("t3_a", false)])
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
        #expect(!store.isSaved("t3_a", loaded: false))
        #expect(store.vote(for: "t3_b", loaded: 0) == 0)
    }

    @Test("An older fetch that lands after a newer one doesn't undo it")
    func olderFetchLoses() async {
        let store = EngagementStore()
        let log = Log()
        await store.submitVote(1, for: "t3_a", loaded: 0, send: {}, onFailure: log.fail).value
        await store.submitSave(true, for: "t3_a", loaded: false, send: {}, onFailure: log.fail).value
        let older = Date.now
        let newer = older.addingTimeInterval(1)

        store.reconcile(fetchStartedAt: newer, votes: [("t3_a", -1)], saves: [("t3_a", false)])
        store.reconcile(fetchStartedAt: older, votes: [("t3_a", 1)], saves: [("t3_a", true)])
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
        #expect(!store.isSaved("t3_a", loaded: false))
    }

    @Test("A fetch while a write is pending doesn't override it")
    func pendingWriteIgnoresFetch() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        await store.submitVote(1, for: "t3_a", loaded: 0, send: {}, onFailure: log.fail).value
        let down = store.submitVote(-1, for: "t3_a", loaded: 0, send: { await gate.wait() }, onFailure: log.fail)

        await gate.waitUntilStarted()
        store.reconcile(fetchStartedAt: .now, votes: [("t3_a", 1)])
        #expect(store.vote(for: "t3_a", loaded: 0) == -1)
        gate.open()
        await down.value
    }

    @Test("An ambiguous Unsave then a failed Save reports the failure, and a later fetch corrects the bookmark")
    func ambiguousFailureIsReportedAndReconciled() async {
        let store = EngagementStore()
        let gate = Gate()
        let log = Log()
        // Reddit applied this Unsave, but its response timed out.
        let unsave = store.submitSave(false, for: "t3_a", loaded: true, send: {
            await gate.wait()
            throw URLError(.timedOut)
        }, onFailure: log.fail)
        let save = store.submitSave(true, for: "t3_a", loaded: true, send: {
            throw URLError(.notConnectedToInternet)
        }, onFailure: log.fail)

        await gate.waitUntilStarted()
        gate.open()
        await unsave.value
        await save.value
        #expect(log.failures == 1)

        store.reconcile(fetchStartedAt: .now, saves: [("t3_a", false)])
        #expect(!store.isSaved("t3_a", loaded: true))
    }

    @MainActor
    private final class Log {
        var events: [String] = []
        var failures = 0

        func fail(_: Error) {
            failures += 1
        }
    }
}
