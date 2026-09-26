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
        store.recordSaved(false, for: "t3_b")

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

    @Test("When a vote and its undo both fail, nothing rolls back past Reddit's state")
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
        #expect(log.failures == 0)
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

    @MainActor
    private final class Log {
        var events: [String] = []
        var failures = 0

        func fail(_: Error) {
            failures += 1
        }
    }
}
