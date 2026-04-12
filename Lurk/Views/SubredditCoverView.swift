import SwiftUI

struct SubredditCoverView: View {
    let subreddit: String
    let title: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let session: RedditSession
    let subStore: SubredditStore
    let onClose: () -> Void

    private var isJoined: Bool {
        subStore.subreddits.contains { $0.lowercased() == subreddit.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onClose() } label: {
                    Text("Close")
                        .foregroundStyle(Theme.primary)
                }
                Spacer()
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    let action = isJoined ? "unsub" : "sub"
                    if isJoined {
                        subStore.removeSubreddit(matching: subreddit)
                    } else {
                        subStore.addSubreddit(subreddit)
                    }
                    if session.isLoggedIn {
                        let request = session.authenticatedRequest(
                            url: RedditAPI.subscribe,
                            formData: ["action": action, "sr_name": subreddit, "api_type": "json"]
                        )
                        Task { try? await client.execute(request) }
                    }
                } label: {
                    Text(isJoined ? "Leave" : "Join")
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                Theme.border.frame(height: 1)
            }
            SubredditFeedView(subreddit: subreddit, client: client, filterStore: filterStore, subStore: subStore, session: session)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
