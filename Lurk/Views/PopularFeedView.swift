import SwiftUI

struct PopularFeedView: View {
    @Environment(\.redditClient) private var client

    var body: some View {
        PaginatedFeedView { after in
            try await client.fetchPopularPosts(after: after)
        }
    }
}
