import SwiftUI

struct HomeFeedView: View {
    @Environment(\.redditClient) private var client

    var body: some View {
        PaginatedFeedView(subredditNavigation: .push) { after in
            try await client.fetchHomePosts(after: after)
        }
    }
}
