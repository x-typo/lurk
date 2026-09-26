import SwiftUI

struct SubredditFeedView: View {
    let subreddit: String
    @Environment(\.redditClient) private var client

    var body: some View {
        PaginatedFeedView(subredditNavigation: .none, applyBlockFilter: false) { after in
            try await client.fetchSubredditPosts(subreddit, after: after)
        }
        .id(subreddit.lowercased())
    }
}
