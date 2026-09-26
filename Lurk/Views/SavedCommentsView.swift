import SwiftUI

struct SavedCommentsView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [SavedComment] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var thread: ThreadTarget?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
                } else if comments.isEmpty {
                    Text("No saved comments").foregroundStyle(Theme.textMuted).frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(comments) { comment in
                                SavedCommentCard(comment: comment, openThread: { thread = $0 }) { id in
                                    withAnimation { comments.removeAll { $0.id == id } }
                                }
                                .onAppear {
                                    if comment.id == comments.last?.id {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                            if loadingMore {
                                ProgressView().tint(Theme.primary).padding()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                    .refreshable { await loadComments() }
                }
            }
            .background(Theme.background)
            .task { await loadComments() }
            .navigationTitle("Saved Comments")
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
        .sheet(item: $thread) { target in
            ThreadView(target: target)
        }
    }

    private func loadComments() async {
        do {
            guard let username = session.username else { throw URLError(.userAuthenticationRequired) }
            let listing = try await client.fetchSavedComments(username: username)
            comments = listing.data.children.map(\.data)
            after = listing.data.after
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, let after, let username = session.username else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let listing = try await client.fetchSavedComments(username: username, after: after)
            comments.append(contentsOf: listing.data.children.map(\.data))
            self.after = listing.data.after
        } catch {}
    }
}

private struct SavedCommentCard: View {
    let comment: SavedComment
    let openThread: (ThreadTarget) -> Void
    let onUnsave: (String) -> Void

    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @State private var isUnsaving = false

    private var target: ThreadTarget? { ThreadTarget(permalink: comment.permalink) }
    @State private var unsaveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let target { openThread(target.wholePost) }
            } label: {
                Text(comment.linkTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .disabled(target == nil)

            HStack(spacing: 6) {
                Text(comment.subredditNamePrefixed)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Text("\u{2022}")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                Text("u/\(comment.author)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("\u{2022}")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                Text(Formatters.timeAgo(comment.createdUtc))
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            CommentBodyView(
                content: comment.body,
                textFont: .subheadline,
                nonInteractiveTapAction: target.map { target in
                    CommentBodyTapAction(
                        perform: { openThread(target) },
                        mediaAccessibility: MediaActionAccessibility(
                            label: "Open comment thread",
                            hint: "Double-tap to open this comment's thread."
                        )
                    )
                }
            )

            HStack {
                Label(Formatters.score(comment.score), systemImage: "arrow.up")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    Task { await unsaveComment() }
                } label: {
                    if isUnsaving {
                        ProgressView().tint(Theme.swipeHide)
                    } else {
                        Text("Unsave")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.swipeHide)
                    }
                }
                .disabled(isUnsaving)
            }

            if let unsaveError {
                Text(unsaveError)
                    .font(.caption)
                    .foregroundStyle(Theme.swipeHide)
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func unsaveComment() async {
        guard !isUnsaving else { return }
        unsaveError = nil
        guard session.isLoggedIn else {
            unsaveError = "Log in to Reddit to unsave comments."
            return
        }
        isUnsaving = true
        defer { isUnsaving = false }

        do {
            let request = session.authenticatedRequest(
                url: RedditAPI.unsave,
                formData: ["id": "t1_\(comment.id)"]
            )
            try await client.execute(request)
            onUnsave(comment.id)
        } catch {
            unsaveError = error.localizedDescription
        }
    }
}
