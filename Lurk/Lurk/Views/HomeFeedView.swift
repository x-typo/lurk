import SwiftUI

struct HomeFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore

    @State private var posts: [Post] = []
    @State private var loading = true
    @State private var error: String?

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
                            PostCardView(post: post) { id in
                                filterStore.hidePost(id)
                                withAnimation { posts.removeAll { $0.id == id } }
                            }
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
