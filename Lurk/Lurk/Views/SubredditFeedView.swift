import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    let client: RedditClient
    let filterStore: PostFilterStore

    var body: some View {
        PaginatedFeedView(filterStore: filterStore) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
    }
}
