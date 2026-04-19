import SwiftUI

struct BlockedSubredditsView: View {
    @Environment(BlockedSubredditStore.self) private var blockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if blockStore.sortedNames.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "nosign")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.textMuted)
                            Text("No blocked subreddits")
                                .font(.body)
                                .foregroundStyle(Theme.textMuted)
                            Text("Block a subreddit from its feed to silence it in your Home and Popular feeds.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(blockStore.sortedNames, id: \.self) { name in
                            HStack {
                                Text("r/\(name)")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Button {
                                    withAnimation { blockStore.unblock(name) }
                                } label: {
                                    Text("Unblock")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                            .padding(16)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Blocked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
