import SwiftUI

struct HomeFeedView: View {
    @Environment(\.redditClient) private var client
    @Environment(SubredditStore.self) private var subStore

    var body: some View {
        PaginatedFeedView { after in
            try await client.fetchHomePosts(subreddits: subStore.subreddits, after: after)
        }
    }
}
