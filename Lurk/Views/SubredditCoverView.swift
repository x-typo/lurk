import SwiftUI

struct SubredditCoverView: View {
    let subreddit: String
    let title: String
    let onClose: () -> Void

    @Environment(RedditSession.self) private var session
    @Environment(SubredditStore.self) private var subStore
    @Environment(BlockedSubredditStore.self) private var blockStore
    @Environment(\.redditClient) private var client

    @State private var isPending = false
    @State private var syncError: String?

    private var isJoined: Bool {
        subStore.subreddits.contains { $0.lowercased() == subreddit.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 16) {
                    Button { onClose() } label: {
                        Text("Close")
                            .foregroundStyle(Theme.primary)
                    }
                    Spacer()
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
                            onClose()
                        } label: {
                            Label("Block r/\(subreddit)", systemImage: "nosign")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                Theme.border.frame(height: 1)
            }
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
        .preferredColorScheme(.dark)
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
