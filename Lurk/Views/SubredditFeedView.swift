import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let blockStore: BlockedSubredditStore
    let session: RedditSession

    var body: some View {
        PaginatedFeedView(filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session, client: client, showSubredditNav: false, applyBlockFilter: false) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
    }
}
