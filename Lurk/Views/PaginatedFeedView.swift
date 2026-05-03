import SwiftUI

struct PostRemoveAction {
    let label: String
    let apiURL: URL
    var onComplete: ((String) -> Void)? = nil
}

struct PaginatedFeedView: View {
    var showSubredditNav: Bool = true
    var applyFilters: Bool = true
    var applyBlockFilter: Bool = true
    var removeAction: PostRemoveAction? = nil
    let fetchPage: (_ after: String?) async throws -> RedditListing

    @Environment(PostFilterStore.self) private var filterStore
    @Environment(BlockedSubredditStore.self) private var blockStore
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client

    @State private var posts: [Post] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var selectedPost: Post?
    @State private var subredditPost: Post?
    @State private var galleryPost: Post?
    @State private var writeError: String?

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(posts) { post in
                            PostCardView(
                                post: post,
                                onHide: { _ in hidePost(post) },
                                onShowDetail: { selectedPost = post },
                                onShowSubreddit: showSubredditNav ? { subredditPost = post } : nil,
                                onShowGallery: { galleryPost = post }
                            )
                            .onAppear {
                                if post.id == posts.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if loadingMore {
                            ProgressView().tint(Theme.primary).padding()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                .refreshable { await loadPosts() }
            }
        }
        .background(Theme.background)
        .task { await loadPosts() }
        .sheet(item: $selectedPost) { post in
            PostDetailView(
                post: post,
                removeAction: removeAction.map { action in
                    PostRemoveAction(label: action.label, apiURL: action.apiURL) { id in
                        action.onComplete?(id)
                        posts.removeAll { $0.id == id }
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

    private func hidePost(_ post: Post) {
        let removedIndex = posts.firstIndex { $0.id == post.id }
        filterStore.hidePost(post.id)
        posts.removeAll { $0.id == post.id }

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
        guard !posts.contains(where: { $0.id == post.id }) else { return }
        posts.insert(post, at: min(index ?? posts.count, posts.count))
    }

    private func filteredPosts(from listing: RedditListing) -> [Post] {
        let pagePosts = listing.data.children.map(\.data)
        guard applyFilters else { return pagePosts }
        return pagePosts.filter {
            !filterStore.isHidden($0.id)
                && !$0.matchesFilteredKeyword
                && (!applyBlockFilter || !blockStore.isBlocked($0.subreddit))
        }
    }

    private func loadPosts() async {
        do {
            let listing = try await fetchPage(nil)
            posts = filteredPosts(from: listing)
            after = listing.data.after
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, let after else { return }
        loadingMore = true
        do {
            let listing = try await fetchPage(after)
            posts.append(contentsOf: filteredPosts(from: listing))
            self.after = listing.data.after
        } catch {
            // Silent fail on pagination
        }
        loadingMore = false
    }
}
