import SwiftUI

struct SavedPostsView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaginatedFeedView(
                applyFilters: false,
                removeAction: PostRemoveAction(label: "Unsave", apiURL: RedditAPI.unsave, systemImage: "bookmark.slash")
            ) { after in
                guard let username = session.username else { throw URLError(.userAuthenticationRequired) }
                return try await client.fetchSavedPosts(username: username, after: after)
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .status) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.medium))
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
