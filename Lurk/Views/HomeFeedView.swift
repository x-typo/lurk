import SwiftUI

struct HomeFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let session: RedditSession

    @State private var posts: [Post] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedPost: Post?
    @State private var subredditPost: Post?
    @State private var galleryPost: Post?

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
            } else if subStore.subreddits.isEmpty {
                VStack(spacing: 8) {
                    Text("No subreddits followed")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("Add some in the Subreddits tab")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxHeight: .infinity)
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
                                onShowSubreddit: { subredditPost = post },
                                onShowGallery: { galleryPost = post }
                            )
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
            PostDetailView(post: post, session: session, client: client, filterStore: filterStore)
        }
        .fullScreenCover(item: $subredditPost) { post in
            VStack(spacing: 0) {
                HStack {
                    Button { subredditPost = nil } label: {
                        Text("Close")
                            .foregroundStyle(Theme.primary)
                    }
                    Spacer()
                    Text(post.subredditNamePrefixed)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("Close").hidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.background)
                .overlay(alignment: .bottom) {
                    Theme.border.frame(height: 1)
                }
                SubredditFeedView(subreddit: post.subreddit, client: client, filterStore: filterStore, session: session)
            }
            .background(Theme.background)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $galleryPost) { post in
            GalleryViewerView(urls: post.galleryURLs)
        }
    }

    private func loadPosts() async {
        guard !subStore.subreddits.isEmpty else {
            loading = false
            return
        }
        do {
            let listings = try await withThrowingTaskGroup(of: RedditListing.self) { group in
                for sub in subStore.subreddits {
                    group.addTask { try await client.fetchSubredditPosts(sub) }
                }
                var results: [RedditListing] = []
                for try await listing in group { results.append(listing) }
                return results
            }
            posts = listings
                .flatMap { $0.data.children.map(\.data) }
                .filter { !filterStore.isHidden($0.id) }
                .sorted { $0.createdUtc > $1.createdUtc }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
