import SwiftUI

struct SettingsView: View {
    let session: RedditSession
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore

    @State private var showLogin = false
    @State private var showHidden = false
    @State private var savedExpanded = false
    @State private var showSavedPosts = false
    @State private var showSavedComments = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Account")
                        .font(.headline)
                        .foregroundStyle(Theme.text)

                    if session.isLoggedIn {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("u/\(session.username ?? "")")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.text)
                                Text("Signed in")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Button("Sign Out") {
                                Task { await session.logout() }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.swipeHide)
                        }
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("Sign in to Reddit")
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Text("Sign in to sync hidden posts to your Reddit account")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile")
                        .font(.headline)
                        .foregroundStyle(Theme.text)

                    Button {
                        if session.isLoggedIn {
                            showHidden = true
                        } else {
                            showLogin = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "eye.slash.fill")
                                .font(.body)
                                .foregroundStyle(Theme.primary)
                            Text("Hidden")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        if session.isLoggedIn {
                            withAnimation(.easeInOut(duration: 0.2)) { savedExpanded.toggle() }
                        } else {
                            showLogin = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .font(.body)
                                .foregroundStyle(Theme.primary)
                            Text("Saved")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textMuted)
                                .rotationEffect(.degrees(savedExpanded ? 90 : 0))
                        }
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if savedExpanded {
                        VStack(spacing: 8) {
                            Button { showSavedPosts = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.primary)
                                    Text("Saved Posts")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(14)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button { showSavedComments = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.primary)
                                    Text("Saved Comments")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(14)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showLogin) {
            RedditLoginView(session: session)
        }
        .fullScreenCover(isPresented: $showHidden) {
            HiddenPostsView(session: session, client: client, filterStore: filterStore, subStore: subStore)
        }
        .fullScreenCover(isPresented: $showSavedPosts) {
            SavedPostsView(session: session, client: client, filterStore: filterStore, subStore: subStore)
        }
        .fullScreenCover(isPresented: $showSavedComments) {
            SavedCommentsView(session: session, client: client)
        }
    }
}
