import SwiftUI

struct PopularFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore

    var body: some View {
        PaginatedFeedView(filterStore: filterStore) { after in
            try await client.fetchPopularPosts(after: after)
        }
    }
}
