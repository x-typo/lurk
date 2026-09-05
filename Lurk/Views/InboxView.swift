import SwiftUI

struct InboxView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client

    var body: some View {
        let account = session.isLoggedIn ? session.username : nil
        InboxContentView(account: account, fetchPage: { filter, after in
            guard let account, session.isLoggedIn, session.username == account else {
                throw URLError(.userAuthenticationRequired)
            }
            return try await client.fetchInboxReplies(filter: filter, after: after)
        }, markRead: { reply in
            guard let account, session.isLoggedIn, session.username == account else {
                throw URLError(.userAuthenticationRequired)
            }
            let request = session.authenticatedRequest(
                url: RedditAPI.readMessage, formData: ["id": reply.thingID]
            )
            try await client.execute(request)
        })
    }
}

struct InboxContentView: View {
    let account: String?
    let fetchPage: InboxStore.FetchPage
    let markRead: @MainActor (InboxReply) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @State private var store = InboxStore()
    @State private var filter: InboxFilter = .unread
    @State private var subredditReply: InboxReply?
    @State private var replyingTo: InboxReply?
    @State private var playbackSuspension: InlineGIFPlaybackSuspension?

    private struct Selection: Equatable {
        let filter: InboxFilter
        let account: String?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Replies", selection: $filter) {
                        ForEach(InboxFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(filter == .unread
                         ? "Replies stay unread until you mark them read."
                         : "Your comment reply history.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(16)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let error = store.error {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Couldn’t load replies", systemImage: "exclamationmark.circle")
                                    .font(.headline)
                                Text(error).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                Button("Try again") { Task { await reload() } }
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }

                        if store.replies.isEmpty {
                            if store.isLoading || (!store.hasLoaded && store.error == nil) {
                                ProgressView("Loading replies…")
                                    .tint(Theme.primary)
                                    .padding(.top, 100)
                            } else if store.error == nil {
                                emptyState
                            }
                        }

                        ForEach(store.replies) { reply in
                            InboxReplyRow(
                                reply: reply,
                                isMarkingRead: store.markingReadIDs.contains(reply.id),
                                showSubreddit: { presentSubreddit(reply) },
                                replyToComment: { presentReply(to: reply) },
                                markRead: {
                                    Task {
                                        await store.markRead(reply) { try await markRead(reply) }
                                    }
                                }
                            )
                        }

                        if let error = store.paginationError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if store.after != nil {
                            Button {
                                Task { await store.loadMore(fetchPage: fetchPage) }
                            } label: {
                                HStack {
                                    if store.isLoadingMore { ProgressView().tint(Theme.primary) }
                                    Text(store.paginationError == nil ? "Load more replies" : "Try loading more again")
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(store.isLoading || store.isLoadingMore)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await reload() }
                .id(filter)
            }
            .background(Theme.background)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(Theme.primary)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task(id: Selection(filter: filter, account: account)) { await reload() }
        .onDisappear {
            guard subredditReply == nil, replyingTo == nil else { return }
            store.cancel()
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
        .alert("Couldn’t mark reply as read", isPresented: Binding(
            get: { store.writeError != nil },
            set: { if !$0 { store.clearWriteError() } }
        )) {
            Button("OK") { store.clearWriteError() }
        } message: {
            Text(store.writeError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.after != nil ? "tray" : (filter == .unread ? "checkmark.circle" : "tray"))
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.primary)
                .padding(.bottom, 4)
            Text(store.after != nil ? "More replies may be available" : (filter == .unread ? "You’re all caught up" : "No replies yet"))
                .font(.title3.weight(.semibold))
            Text(store.after != nil ? "Keep going to find comment replies." : (filter == .unread ? "New comment replies will appear here." : "Replies to your comments will appear here."))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 80)
    }

    private func reload() async {
        await store.load(filter: filter, account: account, fetchPage: fetchPage)
    }

    private func presentSubreddit(_ reply: InboxReply) {
        playbackSuspension = playbackStore.suspend()
        subredditReply = reply
    }

    private func presentReply(to reply: InboxReply) {
        playbackSuspension = playbackStore.suspend()
        replyingTo = reply
    }

    private func resumeInlineGIFPlayback() {
        playbackSuspension?.invalidate()
        playbackSuspension = nil
    }
}

private struct InboxReplyRow: View {
    let reply: InboxReply
    let isMarkingRead: Bool
    let showSubreddit: () -> Void
    let replyToComment: () -> Void
    let markRead: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(reply.subredditNamePrefixed, action: showSubreddit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Spacer(minLength: 4)
                Text(Formatters.timeAgo(reply.createdUtc))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("u/\(reply.author)")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if reply.isUnread {
                        Circle().fill(Theme.primary).frame(width: 7, height: 7)
                            .accessibilityLabel("Unread")
                    }
                }
                if let url = reply.fullCommentsURL {
                    Button { openURL(url) } label: {
                        Text(reply.linkTitle)
                            .multilineTextAlignment(.leading)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text(reply.linkTitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            CommentBodyView(content: reply.body, textFont: .body)

            Rectangle().fill(Theme.border).frame(height: 1)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { actions }
                    .font(.subheadline.weight(.medium))
            } else {
                HStack(spacing: 16) { actions }
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(reply.isUnread ? Theme.primary.opacity(0.25) : Theme.border.opacity(0.6), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let url = reply.contextURL {
            Button { openURL(url) } label: {
                Label("Context", systemImage: "arrow.up.right")
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: 44)
        }
        Button(action: replyToComment) {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(minHeight: 44)
        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        if reply.isUnread {
            Button(action: markRead) {
                HStack(spacing: 5) {
                    if isMarkingRead {
                        ProgressView().tint(Theme.primary)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                    Text("Mark read")
                }
            }
            .disabled(isMarkingRead)
            .frame(minHeight: 44)
        }
    }
}
