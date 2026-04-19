import SwiftUI

struct PopularFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let blockStore: BlockedSubredditStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session, client: client) { after in
            try await client.fetchPopularPosts(after: after)
        }
    }
}
