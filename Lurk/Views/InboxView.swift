import SwiftUI

struct InboxView: View {
    private static let emptyReplyPageLimit = 5

    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore

    @State private var replies: [InboxReply] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var subredditReply: InboxReply?
    @State private var replyingTo: InboxReply?
    @State private var playbackSuspension: InlineGIFPlaybackSuspension?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
                } else if replies.isEmpty {
                    Text("No replies").foregroundStyle(Theme.textMuted).frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(replies) { reply in
                                InboxReplyRow(
                                    reply: reply,
                                    showSubreddit: { presentSubreddit(reply) },
                                    replyToComment: { presentReply(to: reply) }
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
        .onDisappear {
            guard !isPresentingContent else { return }
            resumeInlineGIFPlayback()
        }
        .fullScreenCover(item: $subredditReply, onDismiss: resumeInlineGIFPlayback) { reply in
            SubredditCoverView(subreddit: reply.subreddit, title: reply.subredditNamePrefixed) {
                subredditReply = nil
            }
        }
        .sheet(item: $replyingTo, onDismiss: resumeInlineGIFPlayback) { reply in
            ComposeReplySheet(
                thingID: reply.thingID,
                isPresented: Binding(
                    get: { replyingTo != nil },
                    set: { if !$0 { replyingTo = nil } }
                )
            )
        }
    }

    private var isPresentingContent: Bool {
        subredditReply != nil || replyingTo != nil
    }

    private func presentSubreddit(_ reply: InboxReply) {
        suspendInlineGIFPlayback()
        subredditReply = reply
    }

    private func presentReply(to reply: InboxReply) {
        suspendInlineGIFPlayback()
        replyingTo = reply
    }

    private func suspendInlineGIFPlayback() {
        playbackSuspension = playbackStore.suspend()
    }

    private func resumeInlineGIFPlayback() {
        playbackSuspension?.invalidate()
        playbackSuspension = nil
    }

    private func loadReplies() async {
        do {
            guard session.isLoggedIn else { throw URLError(.userAuthenticationRequired) }
            let listing = try await client.fetchInboxReplies()
            replies = listing.data.replies
            after = listing.data.after
            var emptyPageCount = 0
            var previousAfter: String?
            while replies.isEmpty,
                  let nextAfter = after,
                  nextAfter != previousAfter,
                  emptyPageCount < Self.emptyReplyPageLimit {
                previousAfter = nextAfter
                try await loadMoreReplies(after: nextAfter)
                emptyPageCount += 1
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

                if let fullCommentsURL = reply.fullCommentsURL {
                    Button {
                        openURL(fullCommentsURL)
                    } label: {
                        Text(reply.linkTitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                } else {
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
