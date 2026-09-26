import SwiftUI

// A Reddit link's thread inside Lurk: the whole post, or one comment's context with that comment highlighted.
struct ThreadView: View {
    let target: ThreadTarget

    @Environment(\.redditClient) private var client
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var post: Post?
    @State private var loadError: String?
    @State private var attempt = 0

    var body: some View {
        if let post {
            PostDetailView(
                post: post,
                commentsFetch: contextFetch,
                focusedCommentID: target.commentID
            )
        } else {
            NavigationStack {
                Group {
                    if let loadError {
                        VStack(spacing: 12) {
                            Text("Couldn't open this thread")
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                            Text(loadError)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { attempt += 1 }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.primary)
                            if let url = target.sourceURL {
                                Button("Open on Reddit") { openURL(url) }
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                        .padding(24)
                    } else {
                        ProgressView()
                            .tint(Theme.primary)
                            .accessibilityLabel("Loading thread")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.primary)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .task(id: attempt) { await load() }
        }
    }

    // Without a comment, the detail loads the whole thread itself.
    private var contextFetch: CommentLoadStore.Fetch? {
        guard let commentID = target.commentID else { return nil }
        let postID = target.postID
        return { [client] in
            try await client.fetchCommentContext(postID: postID, commentID: commentID)
        }
    }

    private func load() async {
        loadError = nil
        do {
            post = try await client.fetchPost(id: target.postID)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
