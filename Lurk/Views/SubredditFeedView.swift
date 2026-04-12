import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, subStore: subStore, session: session, client: client, showSubredditNav: false) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
    }
}
