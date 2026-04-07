import SwiftUI

struct HomeFeedView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, session: session, client: client) { after in
            try await client.fetchHomePosts(after: after)
        }
    }
}
