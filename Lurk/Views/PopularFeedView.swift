import SwiftUI

struct PopularFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, session: session, client: client) { after in
            try await client.fetchPopularPosts(after: after)
        }
    }
}
