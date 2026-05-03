import SwiftUI

struct SubredditsView: View {
    var resetKey: Int = 0

    @Environment(SubredditStore.self) private var subStore
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client

    @State private var selectedSubreddit: String?
    @State private var newSubName = ""
    @State private var syncingSubreddit: String?
    @State private var syncError: String?

    var body: some View {
        Group {
            if let sub = selectedSubreddit {
                VStack(spacing: 0) {
                    Button {
                        selectedSubreddit = nil
                    } label: {
                        HStack {
                            Text("\u{2190} r/\(sub)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.background)
                        .overlay(alignment: .bottom) {
                            Theme.border.frame(height: 1)
                        }
                    }
                    SubredditFeedView(subreddit: sub)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            TextField("Add subreddit...", text: $newSubName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Theme.surface)
                                .foregroundStyle(Theme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit { addSub() }

                            Button { addSub() } label: {
                                Text("+")
                                    .font(.title2.bold())
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 50, height: 50)
                                    .background(Theme.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(syncingSubreddit != nil)
                        }

                        if let syncError {
                            Text(syncError)
                                .font(.caption)
                                .foregroundStyle(Theme.swipeHide)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(subStore.subreddits, id: \.self) { sub in
                            HStack(spacing: 10) {
                                Button {
                                    selectedSubreddit = sub
                                } label: {
                                    Text("r/\(sub)")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 18)
                                        .padding(.horizontal, 20)
                                        .background(Theme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                Button {
                                    removeSub(sub)
                                } label: {
                                    Group {
                                        if syncingSubreddit?.lowercased() == sub.lowercased() {
                                            ProgressView().tint(Theme.textSecondary)
                                        } else {
                                            Text("\u{2715}")
                                                .font(.callout.bold())
                                        }
                                    }
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(Circle())
                                }
                                .disabled(syncingSubreddit != nil)
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Theme.background)
            }
        }
        .onChange(of: resetKey) { _, _ in
            selectedSubreddit = nil
        }
    }

    private func addSub() {
        guard let stored = SubredditName.normalize(newSubName) else { return }
        guard !subStore.subreddits.contains(where: { $0.lowercased() == stored.lowercased() }) else {
            newSubName = ""
            return
        }

        _ = subStore.addSubreddit(stored)
        newSubName = ""
        syncSubscribe(stored, action: "sub") {
            subStore.removeSubreddit(matching: stored)
        }
    }

    private func removeSub(_ sub: String) {
        subStore.removeSubreddit(sub)
        syncSubscribe(sub, action: "unsub") {
            _ = subStore.addSubreddit(sub)
        }
    }

    private func syncSubscribe(_ name: String, action: String, rollback: @escaping () -> Void) {
        guard session.isLoggedIn else { return }
        let request = session.authenticatedRequest(
            url: RedditAPI.subscribe,
            formData: ["action": action, "sr_name": name, "api_type": "json"]
        )
        syncingSubreddit = name
        syncError = nil
        Task { @MainActor in
            defer { syncingSubreddit = nil }
            do {
                try await client.execute(request)
            } catch {
                rollback()
                syncError = error.localizedDescription
            }
        }
    }
}
