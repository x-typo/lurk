import SwiftUI

struct UserCommentsView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [UserComment] = []
    @State private var after: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var subredditComment: UserComment?
    @State private var editingComment: UserComment?
    @State private var deletingComment: UserComment?
    @State private var deletingID: String?
    @State private var writeError: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary).frame(maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
                } else if comments.isEmpty {
                    Text("No comments").foregroundStyle(Theme.textMuted).frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(comments) { comment in
                                UserCommentRow(
                                    comment: comment,
                                    deletingID: deletingID,
                                    showSubreddit: { subredditComment = comment },
                                    editComment: { editingComment = comment },
                                    deleteComment: { deletingComment = comment }
                                )
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
                    }
                    .refreshable { await loadComments() }
                }
            }
            .background(Theme.background)
            .task { await loadComments() }
            .navigationTitle("Comments")
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
        .sheet(item: $editingComment) { comment in
            EditUserCommentSheet(comment: comment) { updatedBody in
                updateCommentBody(id: comment.id, body: updatedBody)
            }
        }
        .fullScreenCover(item: $subredditComment) { comment in
            SubredditCoverView(subreddit: comment.subreddit, title: comment.subredditNamePrefixed) {
                subredditComment = nil
            }
        }
        .alert("Delete comment?", isPresented: deleteAlertPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let deletingComment {
                    Task { await deleteComment(deletingComment) }
                }
            }
        } message: {
            Text("This removes the comment from Reddit.")
        }
        .alert("Reddit action failed", isPresented: writeErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(writeError ?? "")
        }
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { deletingComment != nil },
            set: { if !$0 { deletingComment = nil } }
        )
    }

    private var writeErrorPresented: Binding<Bool> {
        Binding(
            get: { writeError != nil },
            set: { if !$0 { writeError = nil } }
        )
    }

    private func loadComments() async {
        do {
            guard let username = session.username else { throw URLError(.userAuthenticationRequired) }
            let listing = try await client.fetchUserComments(username: username)
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
            let listing = try await client.fetchUserComments(username: username, after: after)
            comments.append(contentsOf: listing.data.children.map(\.data))
            self.after = listing.data.after
        } catch {}
    }

    private func updateCommentBody(id: String, body: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        comments[index].body = body
    }

    private func deleteComment(_ comment: UserComment) async {
        guard deletingID == nil else { return }
        deletingID = comment.id
        defer {
            deletingID = nil
            deletingComment = nil
        }

        do {
            let request = session.authenticatedRequest(
                url: RedditAPI.deleteComment,
                formData: ["id": "t1_\(comment.id)"]
            )
            try await client.execute(request)
            withAnimation {
                comments.removeAll { $0.id == comment.id }
            }
        } catch {
            writeError = error.localizedDescription
        }
    }
}

private struct UserCommentRow: View {
    let comment: UserComment
    let deletingID: String?
    let showSubreddit: () -> Void
    let editComment: () -> Void
    let deleteComment: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: showSubreddit) {
                    Text(comment.subredditNamePrefixed)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                }
                Text("\u{2022}")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Button {
                    if let postURL = comment.postURL {
                        openURL(postURL)
                    }
                } label: {
                    Text(comment.linkTitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Text(comment.author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Text(comment.actionLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(Formatters.timeAgo(comment.createdUtc))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }

            CommentBodyView(content: comment.body, textFont: .body)
                .contentShape(Rectangle())
                .onTapGesture { openURL(comment.redditURL) }

            HStack(spacing: 14) {
                VoteControlsView(thingID: "t1_\(comment.id)", initialScore: comment.score, inactiveColor: Theme.textMuted)

                Button(action: editComment) {
                    Image(systemName: "pencil")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Edit comment")

                Button(role: .destructive, action: deleteComment) {
                    if deletingID == comment.id {
                        ProgressView().tint(Theme.swipeHide)
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.swipeHide)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                .disabled(deletingID != nil)
                .accessibilityLabel("Delete comment")
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }
}

private struct EditUserCommentSheet: View {
    let commentID: String
    let onSaved: (String) -> Void

    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var saving = false
    @State private var editError: String?

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(comment: UserComment, onSaved: @escaping (String) -> Void) {
        commentID = comment.id
        self.onSaved = onSaved
        _text = State(initialValue: comment.body)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                    .foregroundStyle(Theme.text)
                    .font(.body)
                    .padding(12)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(16)

                if let editError {
                    Text(editError)
                        .font(.caption)
                        .foregroundStyle(Theme.swipeHide)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                Spacer()
            }
            .background(Theme.background)
            .navigationTitle("Edit comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().tint(Theme.primary)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(Theme.primary)
                    .disabled(isEmpty || saving)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onChange(of: text) { _, _ in editError = nil }
    }

    private func save() async {
        guard !isEmpty, !saving else { return }
        editError = nil
        saving = true
        defer { saving = false }

        do {
            let request = session.authenticatedRequest(
                url: RedditAPI.editUserText,
                formData: [
                    "thing_id": "t1_\(commentID)",
                    "text": text,
                    "api_type": "json"
                ]
            )
            try await client.execute(request)
            onSaved(text)
            dismiss()
        } catch {
            editError = error.localizedDescription
        }
    }
}
