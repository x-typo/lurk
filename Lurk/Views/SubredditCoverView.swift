import SwiftUI

struct SubredditCoverView: View {
    let subreddit: String
    let title: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            SubredditPage(subreddit: subreddit, title: title)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        Button("Close") { onClose() }
                            .foregroundStyle(Theme.primary)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

// A subreddit's feed with Join/Leave and Block in the navigation bar. Tabs push it; SubredditCoverView
// hosts it everywhere else.
struct SubredditPage: View {
    let subreddit: String
    let title: String

    @Environment(RedditSession.self) private var session
    @Environment(SubredditStore.self) private var subStore
    @Environment(BlockedSubredditStore.self) private var blockStore
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var isPending = false
    @State private var syncError: String?

    private var isJoined: Bool {
        subStore.subreddits.contains { $0.lowercased() == subreddit.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundStyle(Theme.swipeHide)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            SubredditFeedView(subreddit: subreddit)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await toggleSubscription() }
                } label: {
                    if isPending {
                        ProgressView().tint(Theme.primary)
                    } else {
                        Text(isJoined ? "Leave" : "Join")
                            .foregroundStyle(Theme.primary)
                    }
                }
                .disabled(isPending)
                Menu {
                    Button(role: .destructive) {
                        blockStore.block(subreddit)
                        // Pops a pushed page, or closes the cover when this is its root.
                        dismiss()
                    } label: {
                        Label("Block r/\(subreddit)", systemImage: "nosign")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityLabel("More")
            }
        }
    }

    private func toggleSubscription() async {
        guard !isPending else { return }
        syncError = nil
        let currentlyJoined = isJoined
        let action = currentlyJoined ? "unsub" : "sub"

        guard session.isLoggedIn else {
            applySubscriptionChange(joined: !currentlyJoined)
            return
        }

        isPending = true
        defer { isPending = false }

        do {
            let request = session.authenticatedRequest(
                url: RedditAPI.subscribe,
                formData: ["action": action, "sr_name": subreddit, "api_type": "json"]
            )
            try await client.execute(request)
            applySubscriptionChange(joined: !currentlyJoined)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func applySubscriptionChange(joined: Bool) {
        if joined {
            _ = subStore.addSubreddit(subreddit)
        } else {
            subStore.removeSubreddit(matching: subreddit)
        }
    }
}
