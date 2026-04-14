import SwiftUI

struct PaginatedFeedView: View {
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let session: RedditSession
    let client: RedditClient
    let fetchPage: (_ after: String?) async throws -> RedditListing
    var showSubredditNav: Bool = true

    @State private var posts: [Post] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var selectedPost: Post?
    @State private var subredditPost: Post?
    @State private var galleryPost: Post?

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
                                onHide: { id in
                                    filterStore.hidePost(id) { @MainActor in
                                        guard session.isLoggedIn else { return }
                                        let request = session.authenticatedRequest(
                                            url: RedditAPI.hide,
                                            formData: ["id": "t3_\(id)"]
                                        )
                                        try await client.execute(request)
                                    }
                                    posts.removeAll { $0.id == id }
                                },
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
            PostDetailView(post: post, session: session, client: client, filterStore: filterStore, subStore: subStore)
        }
        .fullScreenCover(item: $subredditPost) { post in
            SubredditCoverView(subreddit: post.subreddit, title: post.subredditNamePrefixed, client: client, filterStore: filterStore, session: session, subStore: subStore) {
                subredditPost = nil
            }
        }
        .fullScreenCover(item: $galleryPost) { post in
            GalleryViewerView(items: post.galleryItems)
        }
    }

    private func filteredPosts(from listing: RedditListing) -> [Post] {
        listing.data.children.map(\.data).filter { !filterStore.isHidden($0.id) && !$0.matchesFilteredKeyword }
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
