import Foundation

@MainActor
@Observable
final class InboxStore {
    typealias FetchPage = @MainActor (InboxFilter, String?) async throws -> InboxListing

    private(set) var replies: [InboxReply] = []
    private(set) var after: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private(set) var paginationError: String?
    private(set) var markingReadIDs: Set<String> = []
    private(set) var writeError: String?

    private var filter: InboxFilter = .unread
    private var account: String?
    private var generation = 0
    private var accountGeneration = 0
    private var visitedCursors: Set<String> = []
    // Preserve reads across overlapping responses; a fresh load reconciles with Reddit.
    private var readIDs: Set<String> = []

    func load(filter: InboxFilter, account: String?, fetchPage: FetchPage) async {
        guard !Task.isCancelled else { return }
        if self.account != account {
            accountGeneration += 1
            markingReadIDs.removeAll()
            writeError = nil
        }
        if self.filter != filter || self.account != account {
            replies = []
            after = nil
            hasLoaded = false
            visitedCursors.removeAll()
        }
        self.filter = filter
        self.account = account
        generation += 1
        readIDs.removeAll()
        isLoading = true
        isLoadingMore = false
        error = nil
        paginationError = nil
        await fetch(replacing: true, generation: generation, fetchPage: fetchPage)
    }

    func loadMore(fetchPage: FetchPage) async {
        guard !isLoading, !isLoadingMore, after != nil, !Task.isCancelled else { return }
        generation += 1
        isLoadingMore = true
        paginationError = nil
        await fetch(replacing: false, generation: generation, fetchPage: fetchPage)
    }

    private func fetch(replacing: Bool, generation requestGeneration: Int, fetchPage: FetchPage) async {
        var cursor = replacing ? nil : after
        var visited = replacing ? Set<String>() : visitedCursors
        defer {
            if generation == requestGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            // Private messages and duplicate-only pages must not masquerade as exhaustion.
            for _ in 0..<5 {
                let listing = try await fetchPage(filter, cursor)
                guard generation == requestGeneration else { return }
                try Task.checkCancellation()
                if let cursor { visited.insert(cursor) }
                let next = listing.data.after
                guard next.map({ !visited.contains($0) }) ?? true else {
                    throw InboxFailure.repeatedCursor
                }
                var ids = replacing ? Set<String>() : Set(replies.map(\.id))
                let incoming = listing.filtered(for: filter).data.replies.compactMap { reply -> InboxReply? in
                    var reply = reply
                    if readIDs.contains(reply.id) { reply.isUnread = false }
                    guard filter != .unread || reply.isUnread,
                          ids.insert(reply.id).inserted else { return nil }
                    return reply
                }
                cursor = next
                if !incoming.isEmpty || next == nil {
                    replies = replacing ? incoming : replies + incoming
                    after = next
                    visitedCursors = visited
                    hasLoaded = true
                    return
                }
            }
            if replacing { replies = [] }
            after = cursor
            visitedCursors = visited
            hasLoaded = true
        } catch {
            guard generation == requestGeneration else { return }
            if !Task.isCancelled, !(error is CancellationError),
               (error as? URLError)?.code != .cancelled {
                if replacing {
                    self.error = Self.message(for: error)
                } else {
                    paginationError = Self.message(for: error)
                }
            }
        }
    }

    func markRead(_ reply: InboxReply, perform: @MainActor () async throws -> Void) async {
        guard reply.isUnread, replies.contains(where: { $0.id == reply.id }),
              !markingReadIDs.contains(reply.id), !Task.isCancelled else { return }
        let writeAccountGeneration = accountGeneration
        markingReadIDs.insert(reply.id)
        writeError = nil
        defer {
            if accountGeneration == writeAccountGeneration {
                markingReadIDs.remove(reply.id)
            }
        }
        do {
            try await perform()
            guard accountGeneration == writeAccountGeneration else { return }
            readIDs.insert(reply.id)
            if filter == .unread {
                replies.removeAll { $0.id == reply.id }
            } else if let index = replies.firstIndex(where: { $0.id == reply.id }) {
                replies[index].isUnread = false
            }
        } catch {
            guard accountGeneration == writeAccountGeneration else { return }
            if !Task.isCancelled, !(error is CancellationError),
               (error as? URLError)?.code != .cancelled {
                writeError = Self.message(for: error)
            }
        }
    }

    func clearWriteError() { writeError = nil }

    private static func message(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "Check your internet connection and try again."
        case .timedOut:
            return "Reddit took too long to respond. Please try again."
        case .userAuthenticationRequired:
            return "Sign in to Reddit and try again."
        default:
            return error.localizedDescription
        }
    }

    func cancel() {
        generation += 1
        isLoading = false
        isLoadingMore = false
    }

    private enum InboxFailure: LocalizedError {
        case repeatedCursor

        var errorDescription: String? {
            "Reddit returned a repeated inbox page. Please try again."
        }
    }
}
