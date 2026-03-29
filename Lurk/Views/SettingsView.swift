import SwiftUI

struct SettingsView: View {
    let session: RedditSession

    @State private var showLogin = false

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
            }
            .padding(16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showLogin) {
            RedditLoginView(session: session)
        }
    }
}
