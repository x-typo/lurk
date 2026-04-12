import SwiftUI

struct SubredditsView: View {
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let session: RedditSession
    var resetKey: Int = 0

    @State private var selectedSubreddit: String?
    @State private var newSubName = ""

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
                    SubredditFeedView(subreddit: sub, client: client, filterStore: filterStore, subStore: subStore, session: session)
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
                                    subStore.removeSubreddit(sub)
                                    syncSubscribe(sub, action: "unsub")
                                } label: {
                                    Text("\u{2715}")
                                        .font(.callout.bold())
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 44, height: 44)
                                        .background(Theme.surfaceElevated)
                                        .clipShape(Circle())
                                }
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
        let name = newSubName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        subStore.addSubreddit(name)
        syncSubscribe(name, action: "sub")
        newSubName = ""
    }

    private func syncSubscribe(_ name: String, action: String) {
        guard session.isLoggedIn else { return }
        let request = session.authenticatedRequest(
            url: RedditAPI.subscribe,
            formData: ["action": action, "sr_name": name, "api_type": "json"]
        )
        Task { try? await client.execute(request) }
    }
}
