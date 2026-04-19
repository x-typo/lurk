import SwiftUI

struct SubredditCoverView: View {
    let subreddit: String
    let title: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let session: RedditSession
    let subStore: SubredditStore
    let blockStore: BlockedSubredditStore
    let onClose: () -> Void

    @State private var isPending = false

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
                        guard !isPending else { return }
                        let currentlyJoined = isJoined
                        let action = currentlyJoined ? "unsub" : "sub"
                        if currentlyJoined {
                            subStore.removeSubreddit(matching: subreddit)
                        } else {
                            guard subStore.addSubreddit(subreddit) != nil else { return }
                        }
                        guard session.isLoggedIn else { return }
                        let request = session.authenticatedRequest(
                            url: RedditAPI.subscribe,
                            formData: ["action": action, "sr_name": subreddit, "api_type": "json"]
                        )
                        isPending = true
                        Task {
                            try? await client.execute(request)
                            isPending = false
                        }
                    } label: {
                        Text(isJoined ? "Leave" : "Join")
                            .foregroundStyle(Theme.primary)
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
            SubredditFeedView(subreddit: subreddit, client: client, filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
