import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    @Environment(\.redditClient) private var client

    var body: some View {
        PaginatedFeedView(showSubredditNav: false, applyBlockFilter: false) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
    }
}
