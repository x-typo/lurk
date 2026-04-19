import SwiftUI

struct HiddenPostsView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaginatedFeedView(
                applyFilters: false,
                removeAction: PostRemoveAction(label: "Unhide", apiURL: RedditAPI.unhide)
            ) { after in
                guard let username = session.username else { throw URLError(.userAuthenticationRequired) }
                return try await client.fetchHiddenPosts(username: username, after: after)
            }
            .navigationTitle("Hidden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.medium))
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
