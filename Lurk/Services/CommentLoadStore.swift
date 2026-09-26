import Foundation

@MainActor
@Observable
final class CommentLoadStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    typealias Fetch = @MainActor () async throws -> [CommentNode]
    typealias FetchMore = @MainActor (CommentMore) async throws -> [CommentNode]

    private(set) var state: State = .idle
    private(set) var nodes: [CommentNode] = []
    private(set) var loadingMoreID: String?
    private(set) var moreErrors: [String: String] = [:]
    private var generation = 0

    func load(fetch: Fetch) async {
        guard state != .loading, state != .loaded, !Task.isCancelled else { return }
        generation += 1
        let requestGeneration = generation
        state = .loading

        do {
            let result = try await fetch()
            guard generation == requestGeneration else { return }
            try Task.checkCancellation()
            nodes = result
            state = .loaded
        } catch {
            guard generation == requestGeneration else { return }
            if Self.isCancellation(error) {
                state = .idle
            } else {
                state = .failed(Self.failureMessage(for: error))
            }
        }
    }

    // Reddit allows one morechildren request at a time, so overlapping requests are ignored.
    func loadMore(_ more: CommentMore, fetch: FetchMore) async {
        guard state == .loaded, loadingMoreID == nil else { return }
        let requestGeneration = generation
        loadingMoreID = more.id
        moreErrors[more.id] = nil
        defer {
            if loadingMoreID == more.id { loadingMoreID = nil }
        }

        do {
            let loaded = try await fetch(more)
            guard generation == requestGeneration else { return }
            let fresh = CommentNode.removingComments(CommentNode.commentIDs(in: nodes), from: loaded)
            nodes = CommentNode.replacing(moreID: more.id, with: fresh, in: nodes)
        } catch {
            guard generation == requestGeneration, !Self.isCancellation(error) else { return }
            moreErrors[more.id] = Self.failureMessage(for: error)
        }
    }

    func cancel() {
        guard state == .loading else { return }
        // A disappearing view can reappear before a cancelled fetch finishes.
        generation += 1
        state = .idle
    }

    private static func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func failureMessage(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost:
            "Check your internet connection and try again."
        case .timedOut:
            "Loading comments took too long. Please try again."
        default:
            error.localizedDescription
        }
    }
}
