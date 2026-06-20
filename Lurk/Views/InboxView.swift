import SwiftUI

struct InboxView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var replies: [InboxReply] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var subredditReply: InboxReply?
    @State private var replyingTo: InboxReply?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
                } else if replies.isEmpty, loadingMore {
                    ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
                } else if replies.isEmpty {
                    Text("No replies").foregroundStyle(Theme.textMuted).frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(replies) { reply in
                                InboxReplyRow(
                                    reply: reply,
                                    showSubreddit: { subredditReply = reply },
                                    replyToComment: { replyingTo = reply }
                                )
                                .onAppear {
                                    if reply.id == replies.last?.id {
                                        Task { await loadMore() }
                                    }
                                }
                            }

                            if loadingMore {
                                ProgressView().tint(Theme.primary).padding()
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .refreshable { await loadReplies() }
                }
            }
            .background(Theme.background)
            .task { await loadReplies() }
            .navigationTitle("Inbox")
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
        .fullScreenCover(item: $subredditReply) { reply in
            SubredditCoverView(subreddit: reply.subreddit, title: reply.subredditNamePrefixed) {
                subredditReply = nil
            }
        }
        .sheet(item: $replyingTo) { reply in
            ComposeReplySheet(
                thingID: reply.thingID,
                isPresented: Binding(
                    get: { replyingTo != nil },
                    set: { if !$0 { replyingTo = nil } }
                )
            )
        }
    }

    private func loadReplies() async {
        do {
            guard session.isLoggedIn else { throw URLError(.userAuthenticationRequired) }
            let listing = try await client.fetchInboxReplies()
            replies = listing.data.replies
            after = listing.data.after
            while replies.isEmpty, after != nil {
                try await loadMoreReplies()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, let after, session.isLoggedIn else { return }
        loadingMore = true
        defer { loadingMore = false }

        do {
            try await loadMoreReplies(after: after)
        } catch {}
    }

    private func loadMoreReplies(after: String? = nil) async throws {
        guard let after = after ?? self.after else { return }
        let listing = try await client.fetchInboxReplies(after: after)
        replies.append(contentsOf: listing.data.replies)
        self.after = listing.data.after
    }
}

private struct InboxReplyRow: View {
    let reply: InboxReply
    let showSubreddit: () -> Void
    let replyToComment: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: showSubreddit) {
                    Text(reply.subredditNamePrefixed)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                }

                Text("\u{2022}")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)

                Button {
                    if let fullCommentsURL = reply.fullCommentsURL {
                        openURL(fullCommentsURL)
                    }
                } label: {
                    Text(reply.linkTitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Text("u/\(reply.author)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Text("replied")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(Formatters.timeAgo(reply.createdUtc))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }

            CommentBodyView(content: reply.body, textFont: .body)

            HStack(spacing: 18) {
                if let contextURL = reply.contextURL {
                    Button("Context") {
                        openURL(contextURL)
                    }
                }

                if let fullCommentsURL = reply.fullCommentsURL {
                    Button("Full Comments") {
                        openURL(fullCommentsURL)
                    }
                }

                Button("Reply", action: replyToComment)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }
}
