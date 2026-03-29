import SwiftUI

struct PaginatedFeedView: View {
    let filterStore: PostFilterStore
    let session: RedditSession
    let client: RedditClient
    let fetchPage: (_ after: String?) async throws -> RedditListing

    @State private var posts: [Post] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?

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
                            PostCardView(post: post, session: session, client: client) { id in
                                filterStore.hidePost(id) { @MainActor in
                                    guard session.isLoggedIn else { return }
                                    let request = session.authenticatedRequest(
                                        url: URL(string: "https://www.reddit.com/api/hide")!,
                                        formData: ["id": "t3_\(id)"]
                                    )
                                    try await client.execute(request)
                                }
                                withAnimation { posts.removeAll { $0.id == id } }
                            }
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
    }

    private func loadPosts() async {
        do {
            let listing = try await fetchPage(nil)
            posts = listing.data.children.map(\.data).filter { !filterStore.isHidden($0.id) }
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
            let newPosts = listing.data.children.map(\.data).filter { !filterStore.isHidden($0.id) }
            posts.append(contentsOf: newPosts)
            self.after = listing.data.after
        } catch {
            // Silent fail on pagination
        }
        loadingMore = false
    }
}
