import SwiftUI

struct UnreadRepliesTabBadge: ViewModifier {
    @Environment(UnreadRepliesStore.self) private var unreadReplies

    func body(content: Content) -> some View {
        content.badge(unreadReplies.hasUnread
            ? Text("•").accessibilityLabel("Unread comment replies")
            : nil)
    }
}
