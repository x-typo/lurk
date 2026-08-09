import SwiftUI

struct PostRemoveAction {
    let label: String
    let apiURL: URL
    var onComplete: ((String) -> Void)? = nil
}

struct PaginatedFeedView: View {
    private enum ReadRequest: Hashable {
        case retryInitial(UUID)
        case refresh(UUID)
        case loadMore(UUID)
        case retryLoadMore(UUID)
    }

    var showSubredditNav: Bool = true
    var applyFilters: Bool = true
    var applyBlockFilter: Bool = true
    var removeAction: PostRemoveAction? = nil
    let fetchPage: @MainActor (_ after: String?) async throws -> RedditListing

    @Environment(PostFilterStore.self) private var filterStore
    @Environment(BlockedSubredditStore.self) private var blockStore
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client

    @State private var pager = FeedPager()
    @State private var selectedPost: Post?
    @State private var subredditPost: Post?
    @State private var galleryPost: Post?
    @State private var writeError: String?
    @State private var readRequest: ReadRequest?

    var body: some View {
        Group {
            if pager.isInitialLoading {
                ProgressView()
                    .tint(Theme.primary)
                    .frame(maxHeight: .infinity)
                    .accessibilityLabel("Loading posts")
            } else if let error = pager.initialError {
                FeedInitialErrorView(message: error) {
                    readRequest = .retryInitial(UUID())
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let refreshError = pager.refreshError {
                            FeedRefreshErrorView(message: refreshError) {
                                readRequest = .refresh(UUID())
                            }
                        } else if pager.posts.isEmpty,
                                  pager.paginationError == nil
                        {
                            let canLoadMore = pager.after != nil
                            FeedEmptyStateView(
                                actionTitle: canLoadMore ? "Load more" : "Refresh",
                                isLoading: pager.isRefreshing || pager.isLoadingMore
                            ) {
                                readRequest = canLoadMore ? .loadMore(UUID()) : .refresh(UUID())
                            }
                        }

                        ForEach(pager.posts) { post in
                            PostCardView(
                                post: post,
                                onHide: { _ in removePost(post) },
                                onShowDetail: { selectedPost = post },
                                onShowSubreddit: showSubredditNav ? { subredditPost = post } : nil,
                                onShowGallery: { galleryPost = post }
                            )
                            .onAppear {
                                requestLoadMoreIfNeeded(for: post)
                            }
                        }

                        if pager.isLoadingMore {
                            ProgressView()
                                .tint(Theme.primary)
                                .padding()
                                .accessibilityLabel("Loading more posts")
                        } else if let paginationError = pager.paginationError,
                                  !pager.isRefreshing
                        {
                            FeedPaginationErrorView(message: paginationError) {
                                readRequest = .retryLoadMore(UUID())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                .refreshable { await refresh() }
            }
        }
        .background(Theme.background)
        .task { await loadInitialIfNeeded() }
        .task(id: readRequest) { await performReadRequest() }
        .sheet(item: $selectedPost) { post in
            PostDetailView(
                post: post,
                removeAction: removeAction.map { action in
                    PostRemoveAction(label: action.label, apiURL: action.apiURL) { id in
                        action.onComplete?(id)
                        pager.removePost(id: id)
                    }
                }
            )
        }
        .fullScreenCover(item: $subredditPost) { post in
            SubredditCoverView(subreddit: post.subreddit, title: post.subredditNamePrefixed) {
                subredditPost = nil
            }
        }
        .fullScreenCover(item: $galleryPost) { post in
            GalleryViewerView(items: post.galleryItems)
        }
        .alert("Reddit action failed", isPresented: writeErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(writeError ?? "")
        }
    }

    private var writeErrorPresented: Binding<Bool> {
        Binding(
            get: { writeError != nil },
            set: { if !$0 { writeError = nil } }
        )
    }

    private func removePost(_ post: Post) {
        if let removeAction {
            performRemoveAction(removeAction, for: post)
        } else {
            hidePost(post)
        }
    }

    private func performRemoveAction(_ action: PostRemoveAction, for post: Post) {
        let removedIndex = pager.posts.firstIndex { $0.id == post.id }
        pager.removePost(id: post.id)

        guard session.isLoggedIn else {
            restoreRemovedPost(post, to: removedIndex)
            writeError = "Log in to Reddit to \(action.label.lowercased()) this post."
            return
        }

        Task { @MainActor in
            do {
                let request = session.authenticatedRequest(
                    url: action.apiURL,
                    formData: ["id": "t3_\(post.id)"]
                )
                try await client.execute(request)
                action.onComplete?(post.id)
            } catch {
                restoreRemovedPost(post, to: removedIndex)
                writeError = error.localizedDescription
            }
        }
    }

    private func hidePost(_ post: Post) {
        let removedIndex = pager.posts.firstIndex { $0.id == post.id }
        filterStore.hidePost(post.id)
        pager.removeFilteredPost(id: post.id)

        guard session.isLoggedIn else { return }

        Task { @MainActor in
            do {
                let request = session.authenticatedRequest(
                    url: RedditAPI.hide,
                    formData: ["id": "t3_\(post.id)"]
                )
                try await client.execute(request)
            } catch {
                restoreHiddenPost(post, to: removedIndex)
                writeError = error.localizedDescription
            }
        }
    }

    private func restoreHiddenPost(_ post: Post, to index: Int?) {
        filterStore.unhidePost(post.id)
        restoreRemovedPost(post, to: index)
    }

    private func restoreRemovedPost(_ post: Post, to index: Int?) {
        pager.restorePost(post, at: index)
    }

    private func shouldInclude(_ post: Post) -> Bool {
        guard applyFilters else { return true }
        return !filterStore.isHidden(post.id)
            && !post.matchesFilteredKeyword
            && (!applyBlockFilter || !blockStore.isBlocked(post.subreddit))
    }

    private func loadInitialIfNeeded() async {
        await pager.loadIfNeeded(fetchPage: fetchPage, include: shouldInclude)
    }

    private func retryInitialLoad() async {
        await pager.retryInitial(fetchPage: fetchPage, include: shouldInclude)
    }

    private func refresh() async {
        await pager.refresh(fetchPage: fetchPage, include: shouldInclude)
    }

    private func loadMore() async {
        await pager.loadMore(fetchPage: fetchPage, include: shouldInclude)
    }

    private func retryLoadMore() async {
        await pager.retryLoadMore(fetchPage: fetchPage, include: shouldInclude)
    }

    private func requestLoadMoreIfNeeded(for post: Post) {
        guard post.id == pager.posts.last?.id,
              !pager.isRefreshing,
              !pager.isLoadingMore,
              pager.paginationError == nil
        else { return }
        readRequest = .loadMore(UUID())
    }

    private func performReadRequest() async {
        guard let readRequest else { return }
        defer {
            if self.readRequest == readRequest {
                self.readRequest = nil
            }
        }
        switch readRequest {
        case .retryInitial:
            await retryInitialLoad()
        case .refresh:
            await refresh()
        case .loadMore:
            await loadMore()
        case .retryLoadMore:
            await retryLoadMore()
        }
    }
}

private struct FeedInitialErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            Text("Couldn't load posts")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeedRefreshErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Couldn't refresh posts")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .tint(Theme.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FeedEmptyStateView: View {
    let actionTitle: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            Text("No posts to show")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("Pull to refresh or try again.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            Button(action: action) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.primary)
                } else {
                    Text(actionTitle)
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .disabled(isLoading)
            .accessibilityLabel(isLoading ? "Loading posts" : actionTitle)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }
}

private struct FeedPaginationErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Couldn't load more posts")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .tint(Theme.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
