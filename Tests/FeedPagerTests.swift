import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Feed pager")
struct FeedPagerTests {
    @Test("Initial failure can be retried")
    func retriesInitialFailure() async throws {
        let page = try listing(postIDs: ["first"], after: "cursor-1")
        let spy = PageSpy(responses: [
            .failure(TestFailure.offline),
            .success(page),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.isEmpty)
        #expect(pager.after == nil)
        #expect(pager.initialError != nil)
        #expect(!pager.isInitialLoading)

        await pager.retryInitial(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-1")
        #expect(pager.initialError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "nil"])
    }

    @Test("Refresh during initial loading is coalesced")
    func coalescesRefreshDuringInitialLoad() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let refreshedPage = try listing(postIDs: ["refreshed"], after: nil)
        let gate = FetchGate()
        let spy = PageSpy(responses: [
            .gated(firstPage, gate),
            .success(refreshedPage),
        ])
        let pager = FeedPager()

        let initialLoad = Task { @MainActor in
            await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(spy.requestedCursors.map(cursorLabel) == ["nil"])
        gate.open()
        await initialLoad.value
        #expect(pager.posts.map(\.id) == ["first"])

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["refreshed"])
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "nil"])
    }

    @Test("Pagination failure preserves state and retries the same cursor")
    func retriesPaginationFailure() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["second"], after: "cursor-2")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .failure(TestFailure.offline),
            .success(secondPage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-1")
        #expect(pager.paginationError != nil)

        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])

        await pager.retryLoadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(pager.after == "cursor-2")
        #expect(pager.paginationError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "cursor-1"])
    }

    @Test("Filtered pages advance until a visible post is found")
    func advancesPastFilteredPages() async throws {
        let filteredPage = try listing(postIDs: ["hidden"], after: "cursor-1")
        let visiblePage = try listing(postIDs: ["visible"], after: "cursor-2")
        let spy = PageSpy(responses: [.success(filteredPage), .success(visiblePage)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { $0.id != "hidden" })

        #expect(pager.posts.map(\.id) == ["visible"])
        #expect(pager.after == "cursor-2")
        #expect(pager.paginationError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])
    }

    @Test("Pages containing only existing post IDs continue to the next cursor")
    func advancesPastDuplicateOnlyPages() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let duplicatePage = try listing(postIDs: ["first"], after: "cursor-2")
        let visiblePage = try listing(postIDs: ["second"], after: "cursor-3")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .success(duplicatePage),
            .success(visiblePage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(pager.after == "cursor-3")
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "cursor-2"])
    }

    @Test("A terminal filtered page finishes without another request")
    func finishesOnTerminalFilteredPage() async throws {
        let page = try listing(postIDs: ["hidden"], after: nil)
        let spy = PageSpy(responses: [.success(page)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in false })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in false })

        #expect(pager.posts.isEmpty)
        #expect(pager.after == nil)
        #expect(pager.paginationError == nil)
        #expect(spy.requestedCursors.count == 1)
    }

    @Test("A repeated cursor pauses automatic pagination")
    func pausesOnRepeatedCursor() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let repeatedPage = try listing(postIDs: ["second"], after: "cursor-1")
        let spy = PageSpy(responses: [.success(firstPage), .success(repeatedPage)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(pager.after == "cursor-1")
        #expect(pager.paginationError != nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])
    }

    @Test("A multi-page cursor cycle pauses automatic pagination")
    func pausesOnCursorCycle() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-a")
        let filteredPage = try listing(postIDs: ["hidden-1"], after: "cursor-b")
        let cyclePage = try listing(postIDs: ["hidden-2"], after: "cursor-a")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .success(filteredPage),
            .success(cyclePage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { !$0.id.hasPrefix("hidden") })
        await pager.loadMore(fetchPage: spy.fetch, include: { !$0.id.hasPrefix("hidden") })
        await pager.loadMore(fetchPage: spy.fetch, include: { !$0.id.hasPrefix("hidden") })

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-a")
        #expect(pager.paginationError != nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-a", "cursor-b"])
    }

    @Test("Filtered-page continuation is capped and can resume manually")
    func capsFilteredPageContinuation() async throws {
        let firstPage = try listing(postIDs: ["hidden-1"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["hidden-2"], after: "cursor-2")
        let visiblePage = try listing(postIDs: ["visible"], after: "cursor-3")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .success(secondPage),
            .success(visiblePage),
        ])
        let pager = FeedPager(maxConsecutiveFilteredPages: 2)

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { !$0.id.hasPrefix("hidden") })

        #expect(pager.posts.isEmpty)
        #expect(pager.after == "cursor-2")
        #expect(pager.paginationError != nil)

        await pager.retryLoadMore(fetchPage: spy.fetch, include: { !$0.id.hasPrefix("hidden") })

        #expect(pager.posts.map(\.id) == ["visible"])
        #expect(pager.after == "cursor-3")
        #expect(pager.paginationError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "cursor-2"])
    }

    @Test("Terminal cursors suppress additional pagination requests")
    func stopsAtTerminalCursor() async throws {
        let page = try listing(postIDs: ["only"], after: nil)
        let spy = PageSpy(responses: [.success(page)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["only"])
        #expect(pager.after == nil)
        #expect(spy.requestedCursors.count == 1)
    }

    @Test("Concurrent load-more triggers share one in-flight request")
    func suppressesConcurrentLoadMore() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["second"], after: nil)
        let gate = FetchGate()
        let spy = PageSpy(responses: [
            .success(firstPage),
            .gated(secondPage, gate),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })

        let firstLoad = Task { @MainActor in
            await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()
        #expect(pager.isLoadingMore)
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])
        gate.open()
        await firstLoad.value

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])
    }

    @Test("Refresh supersedes an in-flight pagination response")
    func refreshesDuringLoadMore() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let stalePage = try listing(postIDs: ["stale"], after: "cursor-2")
        let refreshedPage = try listing(postIDs: ["refreshed"], after: "cursor-3")
        let gate = FetchGate()
        let spy = PageSpy(responses: [
            .success(firstPage),
            .gated(stalePage, gate),
            .success(refreshedPage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let loadMore = Task { @MainActor in
            await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })
        gate.open()
        await loadMore.value

        #expect(pager.posts.map(\.id) == ["refreshed"])
        #expect(pager.after == "cursor-3")
        #expect(!pager.isLoadingMore)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "nil"])
    }

    @Test("A failed refresh preserves loaded content and can be retried")
    func preservesContentAfterRefreshFailure() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let refreshedPage = try listing(postIDs: ["refreshed"], after: "cursor-2")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .failure(TestFailure.offline),
            .success(refreshedPage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-1")
        #expect(pager.initialLoadState == .loaded)
        #expect(pager.refreshError != nil)
        #expect(!pager.isRefreshing)

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["refreshed"])
        #expect(pager.after == "cursor-2")
        #expect(pager.refreshError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "nil", "nil"])
    }

    @Test("A filtered-page cap during refresh preserves content and can continue")
    func preservesContentWhenRefreshHitsFilteredPageCap() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-old")
        let firstFilteredPage = try listing(postIDs: ["hidden-1"], after: "cursor-new-1")
        let secondFilteredPage = try listing(postIDs: ["hidden-2"], after: "cursor-new-2")
        let refreshedPage = try listing(postIDs: ["refreshed"], after: "cursor-new-3")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .success(firstFilteredPage),
            .success(secondFilteredPage),
            .success(refreshedPage),
        ])
        let pager = FeedPager(maxConsecutiveFilteredPages: 2)
        let include: FeedPager.IncludePost = { !$0.id.hasPrefix("hidden") }

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: include)
        await pager.refresh(fetchPage: spy.fetch, include: include)

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-new-2")
        #expect(pager.paginationError != nil)
        #expect(pager.refreshError == nil)
        #expect(!pager.isRefreshing)

        await pager.retryLoadMore(fetchPage: spy.fetch, include: include)

        #expect(pager.posts.map(\.id) == ["first", "refreshed"])
        #expect(pager.after == "cursor-new-3")
        #expect(pager.refreshError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == [
            "nil",
            "nil",
            "cursor-new-1",
            "cursor-new-2",
        ])
    }

    @Test("Initial cancellation returns to idle and reloads on the next task")
    func reloadsAfterInitialCancellation() async throws {
        let page = try listing(postIDs: ["first"], after: nil)
        let spy = PageSpy(responses: [
            .failure(CancellationError()),
            .success(page),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.initialLoadState == .idle)
        #expect(pager.initialError == nil)

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.initialLoadState == .loaded)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "nil"])
    }

    @Test("Cancelling suspended pagination preserves state and permits a retry")
    func cancelsSuspendedPagination() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["second"], after: nil)
        let gate = FetchGate()
        let spy = PageSpy(responses: [
            .success(firstPage),
            .gated(secondPage, gate),
            .success(secondPage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let loadMore = Task { @MainActor in
            await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        loadMore.cancel()
        gate.open()
        await loadMore.value

        #expect(pager.posts.map(\.id) == ["first"])
        #expect(pager.after == "cursor-1")
        #expect(pager.paginationError == nil)
        #expect(!pager.isLoadingMore)

        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(pager.after == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "cursor-1"])
    }

    @Test("Refresh does not reintroduce an optimistically removed post")
    func suppressesRemovedPostsDuringRefresh() async throws {
        let firstPage = try listing(postIDs: ["removed", "kept"], after: "cursor-1")
        let staleRefresh = try listing(postIDs: ["removed", "kept"], after: nil)
        let spy = PageSpy(responses: [.success(firstPage), .success(staleRefresh)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let removedPost = try #require(pager.posts.first { $0.id == "removed" })
        pager.removePost(id: removedPost.id)
        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["kept"])

        pager.restorePost(removedPost, at: 0)
        #expect(pager.posts.map(\.id) == ["removed", "kept"])
    }

    @Test("Shared filter removals can reappear after filter state changes")
    func releasesSharedFilterRemovals() async throws {
        let page = try listing(postIDs: ["post"], after: nil)
        let spy = PageSpy(responses: [.success(page), .success(page)])
        let pager = FeedPager()
        var isHidden = false
        let include: FeedPager.IncludePost = { _ in !isHidden }

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: include)
        isHidden = true
        pager.removeFilteredPost(id: "post")

        #expect(pager.posts.isEmpty)

        isHidden = false
        await pager.refresh(fetchPage: spy.fetch, include: include)

        #expect(pager.posts.map(\.id) == ["post"])
    }

    @Test("Removal during refresh is applied to the suspended response")
    func removesPostDuringRefresh() async throws {
        let page = try listing(postIDs: ["removed", "kept"], after: nil)
        let gate = FetchGate()
        let spy = PageSpy(responses: [.success(page), .gated(page, gate)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let refresh = Task { @MainActor in
            await pager.refresh(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        pager.removePost(id: "removed")
        gate.open()
        await refresh.value

        #expect(pager.posts.map(\.id) == ["kept"])
    }

    @Test("Removal during a cancelled refresh is applied to restored content")
    func removesPostDuringCancelledRefresh() async throws {
        let page = try listing(postIDs: ["removed", "kept"], after: "cursor-1")
        let stalePage = try listing(postIDs: ["stale"], after: "stale-cursor")
        let gate = FetchGate()
        let spy = PageSpy(responses: [.success(page), .gated(stalePage, gate)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let refresh = Task { @MainActor in
            await pager.refresh(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        pager.removePost(id: "removed")
        refresh.cancel()
        gate.open()
        await refresh.value

        #expect(pager.posts.map(\.id) == ["kept"])
        #expect(pager.after == "cursor-1")
        #expect(pager.initialLoadState == .loaded)
        #expect(pager.paginationError == nil)
    }

    @Test("Removal rollback during refresh survives the suspended response")
    func restoresPostDuringRefresh() async throws {
        let page = try listing(postIDs: ["removed", "kept"], after: nil)
        let gate = FetchGate()
        let spy = PageSpy(responses: [.success(page), .gated(page, gate)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let removedPost = try #require(pager.posts.first { $0.id == "removed" })
        pager.removePost(id: removedPost.id)
        let refresh = Task { @MainActor in
            await pager.refresh(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        pager.restorePost(removedPost, at: 0)
        gate.open()
        await refresh.value

        #expect(pager.posts.map(\.id) == ["removed", "kept"])
    }

    @Test("Removal rollback during a cancelled refresh survives restored content")
    func restoresPostDuringCancelledRefresh() async throws {
        let page = try listing(postIDs: ["removed", "kept"], after: "cursor-1")
        let stalePage = try listing(postIDs: ["stale"], after: "stale-cursor")
        let gate = FetchGate()
        let spy = PageSpy(responses: [.success(page), .gated(stalePage, gate)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let removedPost = try #require(pager.posts.first { $0.id == "removed" })
        pager.removePost(id: removedPost.id)
        let refresh = Task { @MainActor in
            await pager.refresh(fetchPage: spy.fetch, include: { _ in true })
        }
        await gate.waitUntilStarted()

        pager.restorePost(removedPost, at: 0)
        refresh.cancel()
        gate.open()
        await refresh.value

        #expect(pager.posts.map(\.id) == ["removed", "kept"])
        #expect(pager.after == "cursor-1")
        #expect(pager.initialLoadState == .loaded)
        #expect(pager.paginationError == nil)
    }

    @Test("Rollback outside content replacement is not pinned into a later refresh")
    func doesNotPersistRollbackIntoLaterRefresh() async throws {
        let firstPage = try listing(postIDs: ["restored", "kept"], after: nil)
        let laterPage = try listing(postIDs: ["kept"], after: nil)
        let spy = PageSpy(responses: [.success(firstPage), .success(laterPage)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        let restoredPost = try #require(pager.posts.first { $0.id == "restored" })
        pager.removePost(id: restoredPost.id)
        pager.restorePost(restoredPost, at: 0)

        #expect(pager.posts.map(\.id) == ["restored", "kept"])

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["kept"])
    }

    @Test("Refresh replaces posts, cursors, and errors")
    func refreshesFromTheFirstPage() async throws {
        let firstPage = try listing(postIDs: ["first"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["second"], after: "cursor-2")
        let refreshedPage = try listing(postIDs: ["refreshed"], after: "cursor-3")
        let spy = PageSpy(responses: [
            .success(firstPage),
            .success(secondPage),
            .failure(TestFailure.offline),
            .success(refreshedPage),
        ])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first", "second"])
        #expect(pager.after == "cursor-2")
        #expect(pager.paginationError != nil)

        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["refreshed"])
        #expect(pager.after == "cursor-3")
        #expect(pager.initialError == nil)
        #expect(pager.paginationError == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1", "cursor-2", "nil"])
    }

    @Test("Optimistic removal can restore a post at its original index")
    func restoresRemovedPost() async throws {
        let page = try listing(postIDs: ["first", "second"], after: nil)
        let spy = PageSpy(responses: [.success(page)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        pager.removePost(id: "first")
        let firstPost = try #require(page.data.children.first?.data)
        pager.restorePost(firstPost, at: 0)

        #expect(pager.posts.map(\.id) == ["first", "second"])
    }

    @Test("Pagination can continue after every visible post is removed")
    func loadsMoreAfterRemovingVisiblePosts() async throws {
        let firstPage = try listing(postIDs: ["first", "second"], after: "cursor-1")
        let secondPage = try listing(postIDs: ["third"], after: nil)
        let spy = PageSpy(responses: [.success(firstPage), .success(secondPage)])
        let pager = FeedPager()

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        pager.removePost(id: "first")
        pager.removePost(id: "second")
        await pager.loadMore(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["third"])
        #expect(pager.after == nil)
        #expect(spy.requestedCursors.map(cursorLabel) == ["nil", "cursor-1"])
    }

    @Test("Optimistic removal tombstones stay within their configured bound")
    func boundsRemovedPostTombstones() async throws {
        let page = try listing(postIDs: ["first", "second", "third"], after: nil)
        let spy = PageSpy(responses: [.success(page), .success(page)])
        let pager = FeedPager(maxRemovedPostIDs: 2)

        await pager.loadIfNeeded(fetchPage: spy.fetch, include: { _ in true })
        pager.removePost(id: "first")
        pager.removePost(id: "second")
        pager.removePost(id: "third")
        await pager.refresh(fetchPage: spy.fetch, include: { _ in true })

        #expect(pager.posts.map(\.id) == ["first"])
    }

    private func cursorLabel(_ cursor: String?) -> String {
        cursor ?? "nil"
    }

    private func listing(postIDs: [String], after: String?) throws -> RedditListing {
        let children: [[String: Any]] = postIDs.map { id in
            [
                "data": [
                    "id": id,
                    "title": "Post \(id)",
                    "author": "reader",
                    "subreddit": "swift",
                    "subreddit_name_prefixed": "r/swift",
                    "score": 1,
                    "num_comments": 0,
                    "created_utc": 1_700_000_000,
                    "permalink": "/r/swift/comments/\(id)/post/",
                    "url": "https://example.com/\(id)",
                    "selftext": "",
                    "is_self": false,
                    "is_video": false,
                    "stickied": false,
                    "over_18": false,
                ],
            ]
        }
        let afterValue: Any = after.map { $0 as Any } ?? NSNull()
        let payload: [String: Any] = [
            "data": [
                "after": afterValue,
                "children": children,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try RedditAPI.decoder.decode(RedditListing.self, from: data)
    }
}

@MainActor
private final class PageSpy {
    enum Response {
        case success(RedditListing)
        case failure(Error)
        case gated(RedditListing, FetchGate)
    }

    private var responses: [Response]
    private(set) var requestedCursors: [String?] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func fetch(after: String?) async throws -> RedditListing {
        requestedCursors.append(after)
        guard !responses.isEmpty else { throw TestFailure.unexpectedRequest }

        switch responses.removeFirst() {
        case .success(let listing):
            return listing
        case .failure(let error):
            throw error
        case .gated(let listing, let gate):
            await gate.waitForOpen()
            return listing
        }
    }
}

@MainActor
private final class FetchGate {
    private var started = false
    private var opened = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitForOpen() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        guard !opened else { return }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func open() {
        opened = true
        openWaiters.forEach { $0.resume() }
        openWaiters.removeAll()
    }
}

private enum TestFailure: LocalizedError {
    case offline
    case unexpectedRequest

    var errorDescription: String? {
        switch self {
        case .offline:
            "The connection is offline."
        case .unexpectedRequest:
            "The test received an unexpected page request."
        }
    }
}
