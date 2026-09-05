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

    typealias Fetch = @MainActor () async throws -> [Comment]

    private(set) var state: State = .idle
    private(set) var comments: [Comment] = []
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
            comments = Array(result.prefix(30))
            state = .loaded
        } catch {
            guard generation == requestGeneration else { return }
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                state = .idle
            } else {
                state = .failed(Self.failureMessage(for: error))
            }
        }
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

    func cancel() {
        guard state == .loading else { return }
        // A disappearing view can reappear before a cancelled fetch finishes.
        generation += 1
        state = .idle
    }
}
