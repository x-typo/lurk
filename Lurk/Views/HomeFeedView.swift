import SwiftUI

struct HomeFeedView: View {
    @Environment(\.redditClient) private var client

    var body: some View {
        PaginatedFeedView { after in
            try await client.fetchHomePosts(after: after)
        }
    }
}
