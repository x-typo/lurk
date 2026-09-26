import SwiftUI

struct MuteListView: View {
    enum Kind: Identifiable {
        case users
        case keywords

        var id: Self { self }
    }

    let kind: Kind

    @Environment(MuteStore.self) private var muteStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var entryError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    addField

                    if let entryError {
                        Text(entryError)
                            .font(.caption)
                            .foregroundStyle(Theme.swipeHide)
                    }

                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.bottom, 8)

                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.textMuted)
                            Text(emptyTitle)
                                .font(.body)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        ForEach(items, id: \.self) { item in
                            HStack {
                                Text(label(for: item))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    withAnimation { remove(item) }
                                } label: {
                                    Text("Unmute")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.primary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Unmute \(label(for: item))")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: entry) { _, _ in entryError = nil }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $entry)
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
                .submitLabel(.done)
                .onSubmit(add)

            Button(action: add) {
                Text("+")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.text)
                    .frame(width: 50, height: 50)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(kind == .users ? "Mute user" : "Mute keyword")
        }
    }

    private var items: [String] {
        kind == .users ? muteStore.users : muteStore.keywords
    }

    private var title: String {
        kind == .users ? "Muted Users" : "Muted Keywords"
    }

    private var placeholder: String {
        kind == .users ? "Username" : "Word or phrase"
    }

    private var emptyTitle: String {
        kind == .users ? "No muted users" : "No muted keywords"
    }

    private var footnote: String {
        switch kind {
        case .users:
            "Hides their posts and comments, including replies to their comments. You can also mute someone by long-pressing their comment. Unmuted posts come back when you refresh a feed."
        case .keywords:
            "Hides posts whose titles contain these words or phrases. Matches whole words and ignores case. Unmuted posts come back when you refresh a feed."
        }
    }

    private func label(for item: String) -> String {
        kind == .users ? "u/\(item)" : item
    }

    private func add() {
        let added = kind == .users ? muteStore.muteUser(entry) : muteStore.muteKeyword(entry)
        if added == nil {
            entryError = kind == .users
                ? "Enter a Reddit username, like AutoModerator."
                : "Enter a word or phrase."
        } else {
            entry = ""
        }
    }

    private func remove(_ item: String) {
        if kind == .users {
            muteStore.unmuteUser(item)
        } else {
            muteStore.unmuteKeyword(item)
        }
    }
}
