import Foundation

// Shared by every feed. Sends each post's hide and unhide writes to Reddit in the order the user
// made them, so a quick hide, Undo, hide can't reach Reddit out of order. When a post's latest write
// fails, onFailure runs only if Reddit's confirmed state differs from what the user last chose.
// A queued write is dropped, and its failure ignored, if the signed-in account changed.
@MainActor
@Observable
final class PostHideSync {
    typealias Send = @MainActor () async throws -> Void

    @ObservationIgnored private var tails: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]
    // Reddit's hidden state for a post after its last completed write.
    @ObservationIgnored private var confirmedHidden: [String: Bool] = [:]

    @discardableResult
    func enqueue(
        postID: String,
        hidden: Bool,
        account: String,
        currentAccount: @escaping @MainActor () -> String?,
        send: @escaping Send,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        let generation = advance(postID)
        let previous = tails[postID]
        if previous == nil {
            // Before this action, Reddit had the opposite state.
            confirmedHidden[postID] = !hidden
        }

        let task = Task { @MainActor in
            await previous?.value
            defer { finish(postID, generation: generation) }
            guard currentAccount() == account else { return }
            do {
                try await send()
                confirmedHidden[postID] = hidden
            } catch {
                guard generations[postID] == generation,
                      currentAccount() == account,
                      confirmedHidden[postID] != hidden else { return }
                onFailure(error)
            }
        }
        tails[postID] = task
        return task
    }

    // A local-only change (signed out) supersedes the failure handling of any queued write.
    func supersede(postID: String) {
        guard tails[postID] != nil else { return }
        advance(postID)
    }

    @discardableResult
    private func advance(_ postID: String) -> Int {
        let generation = (generations[postID] ?? 0) + 1
        generations[postID] = generation
        return generation
    }

    private func finish(_ postID: String, generation: Int) {
        guard generations[postID] == generation else { return }
        generations[postID] = nil
        tails[postID] = nil
        confirmedHidden[postID] = nil
    }
}
