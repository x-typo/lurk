import Foundation

@MainActor
@Observable
final class FeedPager {
    enum InitialLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    typealias FetchPage = @MainActor (_ after: String?) async throws -> RedditListing
    typealias IncludePost = @MainActor (Post) -> Bool

    private struct Batch {
        let posts: [Post]
        let after: String?
        let paginationError: String?
    }

    private struct BatchFailure: Error {
        let underlyingError: Error
        let retryAfter: String?
    }

    private struct ContentSnapshot {
        let posts: [Post]
        let after: String?
        let initialLoadState: InitialLoadState
        let paginationError: String?
        let refreshError: String?
    }

    private struct PendingRestoration {
        let post: Post
        let index: Int?
    }

    private static let continuationMessage = "More posts may be available. Retry to continue."
    private static let repeatedCursorMessage = "Reddit returned the same page again. Retry to try again."

    private(set) var posts: [Post] = []
    private(set) var after: String?
    private(set) var initialLoadState: InitialLoadState = .idle
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var paginationError: String?
    private(set) var refreshError: String?

    private let maxConsecutiveFilteredPages: Int
    private let maxRemovedPostIDs: Int
    private var generation = 0
    private var removedPostIDs = Set<String>()
    private var removedPostOrder: [String] = []
    private var pendingRestorations: [String: PendingRestoration] = [:]

    init(maxConsecutiveFilteredPages: Int = 5, maxRemovedPostIDs: Int = 5_000) {
        self.maxConsecutiveFilteredPages = max(1, maxConsecutiveFilteredPages)
        self.maxRemovedPostIDs = max(1, maxRemovedPostIDs)
    }

    var isInitialLoading: Bool {
        initialLoadState == .idle || initialLoadState == .loading
    }

    var initialError: String? {
        guard case .failed(let message) = initialLoadState else { return nil }
        return message
    }

    func loadIfNeeded(fetchPage: FetchPage, include: IncludePost) async {
        guard initialLoadState == .idle else { return }
        await replaceInitialContent(fetchPage: fetchPage, include: include)
    }

    func retryInitial(fetchPage: FetchPage, include: IncludePost) async {
        guard initialError != nil else { return }
        await replaceInitialContent(fetchPage: fetchPage, include: include)
    }

    func refresh(fetchPage: FetchPage, include: IncludePost) async {
        guard initialLoadState != .loading else { return }
        if initialLoadState == .loaded {
            await refreshContent(fetchPage: fetchPage, include: include)
        } else {
            await replaceInitialContent(fetchPage: fetchPage, include: include)
        }
    }

    func loadMore(fetchPage: FetchPage, include: IncludePost) async {
        guard paginationError == nil else { return }
        await performLoadMore(fetchPage: fetchPage, include: include)
    }

    func retryLoadMore(fetchPage: FetchPage, include: IncludePost) async {
        guard paginationError != nil else { return }
        await performLoadMore(fetchPage: fetchPage, include: include)
    }

    func removePost(id: String) {
        if removedPostIDs.insert(id).inserted {
            removedPostOrder.append(id)
            trimRemovedPostIDsIfNeeded()
        }
        pendingRestorations.removeValue(forKey: id)
        posts.removeAll { $0.id == id }
    }

    func removeFilteredPost(id: String) {
        removedPostIDs.remove(id)
        removedPostOrder.removeAll { $0 == id }
        pendingRestorations.removeValue(forKey: id)
        posts.removeAll { $0.id == id }
    }

    func restorePost(_ post: Post, at index: Int?) {
        removedPostIDs.remove(post.id)
        removedPostOrder.removeAll { $0 == post.id }
        if initialLoadState == .loading || isRefreshing {
            pendingRestorations[post.id] = PendingRestoration(post: post, index: index)
        } else {
            pendingRestorations.removeValue(forKey: post.id)
        }
        guard !posts.contains(where: { $0.id == post.id }) else { return }
        posts.insert(post, at: min(index ?? posts.count, posts.count))
    }

    private func replaceInitialContent(fetchPage: FetchPage, include: IncludePost) async {
        guard initialLoadState != .loading, !isRefreshing else { return }

        let snapshot = ContentSnapshot(
            posts: posts,
            after: after,
            initialLoadState: initialLoadState,
            paginationError: paginationError,
            refreshError: refreshError
        )
        generation += 1
        let operationGeneration = generation

        initialLoadState = .loading
        isLoadingMore = false
        isRefreshing = false
        paginationError = nil
        refreshError = nil
        posts = []
        after = nil

        do {
            let batch = try await fetchBatch(
                startingAfter: nil,
                excludingIDs: [],
                generation: operationGeneration,
                fetchPage: fetchPage,
                include: include
            )
            guard generation == operationGeneration else { return }
            posts = reconciledPosts(from: batch.posts)
            after = batch.after
            paginationError = batch.paginationError
            refreshError = nil
            initialLoadState = .loaded
        } catch let failure as BatchFailure {
            guard generation == operationGeneration else { return }
            if isCancellation(failure.underlyingError) {
                restore(snapshot)
                return
            }
            pendingRestorations.removeAll()
            initialLoadState = .failed(failure.underlyingError.localizedDescription)
        } catch {
            guard generation == operationGeneration else { return }
            if isCancellation(error) {
                restore(snapshot)
                return
            }
            pendingRestorations.removeAll()
            initialLoadState = .failed(error.localizedDescription)
        }
    }

    private func refreshContent(fetchPage: FetchPage, include: IncludePost) async {
        guard initialLoadState == .loaded, !isRefreshing else { return }

        let hadLoadedContent = !posts.isEmpty
        let previousAfter = after
        let previousPaginationError = paginationError
        let previousRefreshError = refreshError
        generation += 1
        let operationGeneration = generation

        isRefreshing = true
        isLoadingMore = false
        refreshError = nil

        do {
            let batch = try await fetchBatch(
                startingAfter: nil,
                excludingIDs: [],
                generation: operationGeneration,
                fetchPage: fetchPage,
                include: include
            )
            guard generation == operationGeneration else { return }
            if hadLoadedContent,
               batch.posts.isEmpty,
                let batchError = batch.paginationError
            {
                posts = reconciledPosts(from: posts.filter(include))
                after = batch.after
                paginationError = batchError
                refreshError = nil
                isRefreshing = false
                return
            }
            posts = reconciledPosts(from: batch.posts)
            after = batch.after
            paginationError = batch.paginationError
            refreshError = nil
            isRefreshing = false
        } catch let failure as BatchFailure {
            guard generation == operationGeneration else { return }
            finishRefreshFailure(
                failure.underlyingError,
                previousAfter: previousAfter,
                previousPaginationError: previousPaginationError,
                previousRefreshError: previousRefreshError
            )
        } catch {
            guard generation == operationGeneration else { return }
            finishRefreshFailure(
                error,
                previousAfter: previousAfter,
                previousPaginationError: previousPaginationError,
                previousRefreshError: previousRefreshError
            )
        }
    }

    private func performLoadMore(fetchPage: FetchPage, include: IncludePost) async {
        guard initialLoadState == .loaded,
              !isRefreshing,
              !isLoadingMore,
              let currentAfter = after
        else { return }

        let operationGeneration = generation
        let previousPaginationError = paginationError
        isLoadingMore = true
        paginationError = nil

        do {
            let batch = try await fetchBatch(
                startingAfter: currentAfter,
                excludingIDs: Set(posts.map(\.id)),
                generation: operationGeneration,
                fetchPage: fetchPage,
                include: include
            )
            guard generation == operationGeneration else { return }
            appendUnique(batch.posts.filter { !removedPostIDs.contains($0.id) })
            posts = reconciledPosts(from: posts)
            after = batch.after
            paginationError = batch.paginationError
            isLoadingMore = false
        } catch let failure as BatchFailure {
            guard generation == operationGeneration else { return }
            if isCancellation(failure.underlyingError) {
                paginationError = previousPaginationError
                isLoadingMore = false
                return
            }
            after = failure.retryAfter ?? currentAfter
            paginationError = failure.underlyingError.localizedDescription
            isLoadingMore = false
        } catch {
            guard generation == operationGeneration else { return }
            if isCancellation(error) {
                paginationError = previousPaginationError
                isLoadingMore = false
                return
            }
            after = currentAfter
            paginationError = error.localizedDescription
            isLoadingMore = false
        }
    }

    private func fetchBatch(
        startingAfter: String?,
        excludingIDs: Set<String>,
        generation operationGeneration: Int,
        fetchPage: FetchPage,
        include: IncludePost
    ) async throws -> Batch {
        var requestAfter = startingAfter
        var consecutiveFilteredPages = 0
        var visitedCursors = Set<String>()
        if let startingAfter {
            visitedCursors.insert(startingAfter)
        }

        while true {
            let listing: RedditListing
            do {
                listing = try await fetchPage(requestAfter)
            } catch {
                throw BatchFailure(underlyingError: error, retryAfter: requestAfter)
            }
            try Task.checkCancellation()
            guard generation == operationGeneration else { throw CancellationError() }

            let visiblePosts = uniquePosts(
                listing.data.children.map(\.data).filter(include)
            ).filter {
                !excludingIDs.contains($0.id) && !removedPostIDs.contains($0.id)
            }
            let nextAfter = listing.data.after

            if let nextAfter, !visitedCursors.insert(nextAfter).inserted {
                return Batch(
                    posts: visiblePosts,
                    after: nextAfter,
                    paginationError: Self.repeatedCursorMessage
                )
            }

            if !visiblePosts.isEmpty || nextAfter == nil {
                return Batch(posts: visiblePosts, after: nextAfter, paginationError: nil)
            }

            consecutiveFilteredPages += 1
            if consecutiveFilteredPages >= maxConsecutiveFilteredPages {
                return Batch(
                    posts: [],
                    after: nextAfter,
                    paginationError: Self.continuationMessage
                )
            }

            requestAfter = nextAfter
        }
    }

    private func uniquePosts(_ candidates: [Post]) -> [Post] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private func appendUnique(_ candidates: [Post]) {
        var seen = Set(posts.map(\.id))
        posts.append(contentsOf: candidates.filter { seen.insert($0.id).inserted })
    }

    private func restore(_ snapshot: ContentSnapshot) {
        posts = reconciledPosts(from: snapshot.posts)
        after = snapshot.after
        initialLoadState = snapshot.initialLoadState
        paginationError = snapshot.paginationError
        refreshError = snapshot.refreshError
        isLoadingMore = false
        isRefreshing = false
    }

    private func finishRefreshFailure(
        _ error: Error,
        previousAfter: String?,
        previousPaginationError: String?,
        previousRefreshError: String?
    ) {
        posts = reconciledPosts(from: posts)
        after = previousAfter
        paginationError = previousPaginationError
        refreshError = isCancellation(error) ? previousRefreshError : error.localizedDescription
        isRefreshing = false
    }

    private func trimRemovedPostIDsIfNeeded() {
        let overflow = removedPostOrder.count - maxRemovedPostIDs
        guard overflow > 0 else { return }
        for id in removedPostOrder.prefix(overflow) {
            removedPostIDs.remove(id)
        }
        removedPostOrder.removeFirst(overflow)
    }

    private func reconciledPosts(from candidates: [Post]) -> [Post] {
        var reconciled = uniquePosts(candidates).filter { !removedPostIDs.contains($0.id) }
        let restorations = pendingRestorations.values.sorted { lhs, rhs in
            let lhsIndex = lhs.index ?? Int.max
            let rhsIndex = rhs.index ?? Int.max
            if lhsIndex == rhsIndex { return lhs.post.id < rhs.post.id }
            return lhsIndex < rhsIndex
        }

        for restoration in restorations {
            guard !removedPostIDs.contains(restoration.post.id),
                  !reconciled.contains(where: { $0.id == restoration.post.id })
            else { continue }
            reconciled.insert(
                restoration.post,
                at: min(restoration.index ?? reconciled.count, reconciled.count)
            )
        }
        pendingRestorations.removeAll()
        return reconciled
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
