import SwiftUI

struct SavedPostsView: View {
    let session: RedditSession
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let blockStore: BlockedSubredditStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaginatedFeedView(
                filterStore: filterStore,
                subStore: subStore,
                blockStore: blockStore,
                session: session,
                client: client,
                applyFilters: false,
                removeAction: PostRemoveAction(label: "Unsave", apiURL: RedditAPI.unsave)
            ) { after in
                guard let username = session.username else { throw URLError(.userAuthenticationRequired) }
                return try await client.fetchSavedPosts(username: username, after: after)
            }
            .navigationTitle("Saved")
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
