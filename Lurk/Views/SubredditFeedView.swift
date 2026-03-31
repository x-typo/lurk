import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, session: session, client: client, showSubredditNav: false) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
    }
}
