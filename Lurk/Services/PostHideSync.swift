import Foundation

// Sends each post's hide and unhide writes to Reddit in the order the user made them, so a quick
// hide, Undo, hide can't reach Reddit out of order. A failure is reported only while it is still
// the post's latest action, and a queued write is dropped if the signed-in account changed.
@MainActor
final class PostHideSync {
    typealias Send = @MainActor () async throws -> Void

    private var tails: [String: Task<Void, Never>] = [:]
    private var generations: [String: Int] = [:]

    @discardableResult
    func enqueue(
        postID: String,
        account: String,
        currentAccount: @escaping @MainActor () -> String?,
        send: @escaping Send,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        let generation = (generations[postID] ?? 0) + 1
        generations[postID] = generation
        let previous = tails[postID]

        let task = Task { @MainActor in
            await previous?.value
            defer {
                if generations[postID] == generation {
                    generations[postID] = nil
                    tails[postID] = nil
                }
            }
            guard currentAccount() == account else { return }
            do {
                try await send()
            } catch {
                guard generations[postID] == generation else { return }
                onFailure(error)
            }
        }
        tails[postID] = task
        return task
    }
}
