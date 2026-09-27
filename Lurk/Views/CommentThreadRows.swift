import SwiftUI
import UIKit

enum CommentSwipeStage: Equatable {
    case none
    case upvote
    case downvote
    case reply
}

struct CommentSwipeState: Equatable {
    private enum Axis: Equatable {
        case horizontal
        case vertical
    }

    static let actionDistance: CGFloat = 60
    static let downvoteDistance: CGFloat = 140
    private static let maxReplyOffset: CGFloat = 120
    private static let maxVoteOffset: CGFloat = 200

    private var axis: Axis?

    // Returns the row offset, or nil once the drag has locked to vertical scrolling.
    mutating func updateDrag(translation: CGSize) -> CGFloat? {
        let resolvedAxis = axis ?? Self.axis(for: translation)
        axis = resolvedAxis
        guard resolvedAxis == .horizontal else { return nil }
        return min(Self.maxReplyOffset, max(-Self.maxVoteOffset, translation.width))
    }

    mutating func endDrag(translation: CGSize) -> CommentSwipeStage {
        let resolvedAxis = axis ?? Self.axis(for: translation)
        axis = nil
        guard resolvedAxis == .horizontal else { return .none }
        return Self.stage(for: translation.width)
    }

    static func stage(for offset: CGFloat) -> CommentSwipeStage {
        if offset <= -downvoteDistance { return .downvote }
        if offset <= -actionDistance { return .upvote }
        if offset >= actionDistance { return .reply }
        return .none
    }

    private static func axis(for translation: CGSize) -> Axis {
        abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
    }
}

struct CommentThreadRowView: View {
    let comment: Comment
    let depth: Int
    let isCollapsed: Bool
    let hiddenReplyCount: Int
    let vote: Int
    let isSelecting: Bool
    let showsSeparator: Bool
    let onToggleCollapse: () -> Void
    let onVote: (Int) -> Void
    let onReply: () -> Void
    let onSelectText: () -> Void
    let onShare: (() -> Void)?
    let onMute: (() -> Void)?
    var isFocused = false
    var isSaved = false
    // Nil when signed out.
    var onSave: (() -> Void)? = nil

    @State private var offset: CGFloat = 0
    @State private var swipe = CommentSwipeState()

    var body: some View {
        ZStack {
            if offset != 0 {
                swipeBackground
            }
            rowContent
                .background(isFocused ? Theme.focusedComment : Theme.background)
                .offset(x: offset)
        }
        .clipped()
        .overlay(alignment: .top) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 0.5)
            }
        }
        .simultaneousGesture(swipeGesture)
        .sensoryFeedback(trigger: swipeStage) { _, stage in
            stage == .none ? nil : .selection
        }
        .contextMenu { menu }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if isCollapsed {
                if hiddenReplyCount > 0 {
                    Text("\(Formatters.score(hiddenReplyCount)) \(hiddenReplyCount == 1 ? "reply" : "replies") hidden")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onToggleCollapse)
                }
            } else {
                CommentBodyView(
                    content: comment.body,
                    nonInteractiveTapAction: CommentBodyTapAction(
                        perform: onToggleCollapse,
                        mediaAccessibility: MediaActionAccessibility(
                            label: "Collapse comment by \(comment.author)",
                            hint: "Double-tap to collapse this comment."
                        )
                    ),
                    isSelecting: isSelecting,
                    gifVideos: comment.gifVideos
                )
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, CommentRails.indent(for: depth))
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            CommentRails(depth: depth)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if isCollapsed {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(comment.author)
                .font(.caption.weight(.semibold))
                .foregroundStyle(authorColor)
                .lineLimit(1)
            if comment.isSubmitter {
                Text("OP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.opBadge)
            }
            Text("\u{00B7}")
                .foregroundStyle(Theme.textMuted)
            scoreLabel
            Text("\u{00B7}")
                .foregroundStyle(Theme.textMuted)
            Text(Formatters.timeAgo(comment.createdUtc))
                .foregroundStyle(Theme.textMuted)
            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.primary)
                    .accessibilityLabel("Saved")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleCollapse)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isCollapsed ? "Expands this comment." : "Collapses this comment.")
        .accessibilityAction { onToggleCollapse() }
        .accessibilityActions {
            Button(vote == 1 ? "Remove upvote" : "Upvote") { onVote(vote == 1 ? 0 : 1) }
            Button(vote == -1 ? "Remove downvote" : "Downvote") { onVote(vote == -1 ? 0 : -1) }
            Button("Reply", action: onReply)
            if let onSave {
                Button(isSaved ? "Unsave" : "Save", action: onSave)
            }
        }
    }

    // Matches the comment's innermost thread line, so each author reads with its reply level.
    private var authorColor: Color {
        CommentRails.innermostColor(depth: depth) ?? Theme.primary
    }

    private var scoreLabel: some View {
        HStack(spacing: 2) {
            if vote != 0 {
                Image(systemName: vote > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
            }
            Text(Formatters.score(comment.displayScore(vote: vote)))
        }
        .foregroundStyle(vote > 0 ? Theme.primary : vote < 0 ? Theme.downvote : Theme.textMuted)
    }

    private var swipeStage: CommentSwipeStage {
        CommentSwipeState.stage(for: offset)
    }

    private var swipeBackground: some View {
        let stage = swipeStage
        let revealsTrailingEdge = offset < 0
        return ZStack(alignment: revealsTrailingEdge ? .trailing : .leading) {
            Rectangle()
                .fill(swipeColor(for: stage))
            Image(systemName: swipeIcon(for: stage, revealsTrailingEdge: revealsTrailingEdge))
                .font(.title3.weight(.bold))
                .foregroundStyle(stage == .none ? Theme.textMuted : .white)
                .padding(.horizontal, 20)
        }
        .accessibilityHidden(true)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard let horizontalOffset = swipe.updateDrag(translation: value.translation) else { return }
                offset = horizontalOffset
            }
            .onEnded { value in
                let stage = swipe.endDrag(translation: value.translation)
                withAnimation(.spring(duration: 0.3)) { offset = 0 }
                switch stage {
                case .upvote:
                    onVote(vote == 1 ? 0 : 1)
                case .downvote:
                    onVote(vote == -1 ? 0 : -1)
                case .reply:
                    onReply()
                case .none:
                    break
                }
            }
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            UIPasteboard.general.string = CommentSpoilers.selectionText(from: comment.body, revealed: [])
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
        Button(action: onSelectText) {
            Label("Select Text", systemImage: "text.cursor")
        }
        if let onShare {
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        if let onSave {
            Button(action: onSave) {
                Label(isSaved ? "Unsave" : "Save", systemImage: isSaved ? "bookmark.slash" : "bookmark")
            }
        }
        if let onMute {
            Button(role: .destructive, action: onMute) {
                Label("Mute u/\(comment.author)", systemImage: "speaker.slash")
            }
        }
    }

    private func swipeColor(for stage: CommentSwipeStage) -> Color {
        switch stage {
        case .none: Theme.surface
        case .upvote: Theme.primary
        case .downvote: Theme.downvote
        case .reply: Theme.swipeReply
        }
    }

    private func swipeIcon(for stage: CommentSwipeStage, revealsTrailingEdge: Bool) -> String {
        switch stage {
        case .upvote: "arrow.up"
        case .downvote: "arrow.down"
        case .reply: "arrowshape.turn.up.left.fill"
        case .none: revealsTrailingEdge ? "arrow.up" : "arrowshape.turn.up.left.fill"
        }
    }
}

struct CommentMoreRowView: View {
    let more: CommentMore
    let depth: Int
    let isLoading: Bool
    let isWaiting: Bool
    let error: String?
    let onLoad: () -> Void

    var body: some View {
        Button(action: onLoad) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.primary)
                    } else {
                        Image(systemName: error == nil ? "chevron.down" : "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                    }
                    Text(title)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.primary)

                if let error, !isLoading {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The store ignores overlapping loads; this only avoids dead taps and the dimmed disabled style.
        .allowsHitTesting(!isLoading && !isWaiting)
        .opacity(isWaiting ? 0.5 : 1)
        .padding(.leading, CommentRails.indent(for: depth))
        .overlay(alignment: .leading) {
            CommentRails(depth: depth)
        }
    }

    private var title: String {
        if isLoading { return "Loading replies\u{2026}" }
        if error != nil { return "Couldn't load replies. Tap to retry." }
        if more.continuesThread { return "Continue thread" }
        let noun = more.isTopLevel ? "comment" : "reply"
        let plural = more.isTopLevel ? "comments" : "replies"
        return "Load \(Formatters.score(more.count)) more \(more.count == 1 ? noun : plural)"
    }
}

struct CommentRails: View {
    let depth: Int

    static func indent(for depth: Int) -> CGFloat {
        let levels = min(depth, Comment.maxIndentDepth)
        return levels == 0 ? 0 : CGFloat(levels) * 10 + 6
    }

    static func color(level: Int) -> Color {
        Theme.commentRails[level % Theme.commentRails.count]
    }

    // The innermost rail beside a comment at `depth`; top-level comments have none.
    static func innermostColor(depth: Int) -> Color? {
        let levels = min(depth, Comment.maxIndentDepth)
        return levels == 0 ? nil : color(level: levels - 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<min(depth, Comment.maxIndentDepth), id: \.self) { level in
                Rectangle()
                    .fill(Self.color(level: level))
                    .frame(width: 2)
            }
        }
        .padding(.leading, 3)
        .accessibilityHidden(true)
    }
}
