import SwiftUI

struct SubredditCoverView: View {
    let subreddit: String
    let title: String
    let client: RedditClient
    let filterStore: PostFilterStore
    let session: RedditSession
    let onClose: () -> Void

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
                Text("Close").hidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                Theme.border.frame(height: 1)
            }
            SubredditFeedView(subreddit: subreddit, client: client, filterStore: filterStore, session: session)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
