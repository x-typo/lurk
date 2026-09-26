import Foundation

// The viewer's votes and saves from this session, keyed by fullname (`t3_…`, `t1_…`). Loaded posts
// keep Reddit's state from their last fetch, so views read through here to show newer choices.
// Like PostHideSync, each thing's writes reach Reddit in the order they were made; when the latest
// fails, the shown value goes back to Reddit's confirmed one. An account change clears everything, and
// work started before it (even for the same account, signed out and back in) can't send or roll back.
@MainActor
@Observable
final class EngagementStore {
    typealias Send = @MainActor () async throws -> Void

    private var votes: [String: Int] = [:]
    private var saves: [String: Bool] = [:]
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var voteLanes = Lanes<Int>()
    @ObservationIgnored private var saveLanes = Lanes<Bool>()

    func vote(for thingID: String, loaded: Int) -> Int {
        votes[thingID] ?? loaded
    }

    func isSaved(_ thingID: String, loaded: Bool) -> Bool {
        saves[thingID] ?? loaded
    }

    @discardableResult
    func submitVote(
        _ vote: Int,
        for thingID: String,
        loaded: Int,
        send: @escaping Send,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        enqueue(vote, for: thingID, in: voteLanes, shown: self.vote(for: thingID, loaded: loaded),
                show: { [weak self] in self?.votes[thingID] = $0 }, send: send, onFailure: onFailure)
    }

    @discardableResult
    func submitSave(
        _ saved: Bool,
        for thingID: String,
        loaded: Bool,
        send: @escaping Send,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        enqueue(saved, for: thingID, in: saveLanes, shown: isSaved(thingID, loaded: loaded),
                show: { [weak self] in self?.saves[thingID] = $0 }, send: send, onFailure: onFailure)
    }

    // Waits until no save writes are queued for the thing, then returns the viewer's final choice.
    func settledSave(_ thingID: String, loaded: Bool) async -> Bool {
        while let tail = saveLanes.tails[thingID] {
            await tail.value
        }
        return isSaved(thingID, loaded: loaded)
    }

    func setAccount(_ account: String?) {
        guard account != self.account else { return }
        self.account = account
        generation += 1
        votes = [:]
        saves = [:]
        voteLanes = Lanes()
        saveLanes = Lanes()
    }

    private final class Lanes<Value: Equatable> {
        var tails: [String: Task<Void, Never>] = [:]
        var sequences: [String: Int] = [:]
        // Reddit's value for a thing after its last completed write.
        var confirmed: [String: Value] = [:]
    }

    private func enqueue<Value: Equatable>(
        _ value: Value,
        for thingID: String,
        in lanes: Lanes<Value>,
        shown: Value,
        show: @escaping @MainActor (Value) -> Void,
        send: @escaping Send,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        let generation = self.generation
        let sequence = (lanes.sequences[thingID] ?? 0) + 1
        lanes.sequences[thingID] = sequence
        let previous = lanes.tails[thingID]
        if previous == nil {
            // Nothing is in flight, so what's shown is Reddit's state.
            lanes.confirmed[thingID] = shown
        }
        show(value)

        let task = Task { @MainActor [weak self] in
            await previous?.value
            defer { Self.finish(thingID, sequence: sequence, in: lanes) }
            guard let self, self.generation == generation else { return }
            do {
                try await send()
                lanes.confirmed[thingID] = value
            } catch {
                guard lanes.sequences[thingID] == sequence, self.generation == generation,
                      let confirmed = lanes.confirmed[thingID], confirmed != value else { return }
                show(confirmed)
                onFailure(error)
            }
        }
        lanes.tails[thingID] = task
        return task
    }

    private static func finish<Value>(_ thingID: String, sequence: Int, in lanes: Lanes<Value>) {
        guard lanes.sequences[thingID] == sequence else { return }
        lanes.tails[thingID] = nil
        lanes.sequences[thingID] = nil
        lanes.confirmed[thingID] = nil
    }
}
