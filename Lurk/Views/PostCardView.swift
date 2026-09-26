import SwiftUI

struct PostCardView: View {
    let post: Post
    var onHide: ((String) -> Void)?
    var onShowDetail: (() -> Void)?
    var onShowSubreddit: (() -> Void)?
    var onShowGallery: (() -> Void)?
    var hideLabel = "Hide"
    var hideSystemImage = "eye.slash"

    @State private var offset: CGFloat = 0
    @State private var interaction = PostCardInteractionState()
    @State private var tapSuppressionResetTask: Task<Void, Never>?
    @State private var collapsing = false
    @Environment(\.openURL) private var openURL
    @Environment(EngagementStore.self) private var engagement

    private let swipeHideOffset: CGFloat = 500

    // Fits inside the capped box when the aspect ratio is known; otherwise keeps the image's own shape.
    @ViewBuilder
    private func feedImage(_ image: Image) -> some View {
        if let aspectRatio = post.imageAspectRatio {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(Post.feedBoxAspectRatio(aspectRatio), contentMode: .fit)
                .background(Theme.background)
        } else {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    var body: some View {
        ZStack {
            if offset != 0 {
                swipeBackground
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        performTap(.showSubreddit)
                    } label: {
                        Text(post.subredditNamePrefixed)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Button {
                        performTap(.showDetail)
                    } label: {
                        Text(Formatters.timeAgo(post.createdUtc))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    performTap(.showDetail)
                } label: {
                    Text(post.title)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let crosspost = post.crosspost {
                    if let originalURL = crosspost.originalURL {
                        Button {
                            performTap(.openExternalURL(originalURL))
                        } label: {
                            CrosspostAttributionLabel(crosspost: crosspost)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the original post in your browser")
                    } else {
                        CrosspostAttributionLabel(crosspost: crosspost)
                    }
                }

                if let externalURL = post.externalLinkURL, let domain = post.externalLinkDomain {
                    Button {
                        performTap(.openExternalURL(externalURL))
                    } label: {
                        HStack(spacing: 4) {
                            Text(domain)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.swipeOpen)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens in browser")
                }

                if let animatedMedia = post.animatedMedia {
                    Group {
                        switch animatedMedia {
                        case .gif(let url):
                            AnimatedGIFView(
                                url: url,
                                posterURL: post.feedImageURL,
                                onMediaTap: { performTap(.showMedia) }
                            )
                                .aspectRatio(Post.feedBoxAspectRatio(post.imageAspectRatio), contentMode: .fit)
                                .background(Theme.background)
                        case .video(let url):
                            Button {
                                performTap(.showMedia)
                            } label: {
                                InlineLoopingVideoView(
                                    url: url,
                                    posterURL: post.feedImageURL,
                                    aspectRatio: Post.feedBoxAspectRatio(post.videoAspectRatio ?? post.imageAspectRatio)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open video")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottom) {
                        if post.galleryItems.count > 1 {
                            GalleryDotIndicator(count: post.galleryItems.count)
                                .allowsHitTesting(false)
                        }
                    }
                } else if let imageURL = post.feedImageURL {
                    Button {
                        performTap(.showMedia)
                    } label: {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                feedImage(image)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                EmptyView()
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.surfaceElevated)
                                    .aspectRatio(Post.feedBoxAspectRatio(post.imageAspectRatio), contentMode: .fit)
                                    .overlay { ProgressView().tint(Theme.textMuted) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .center) {
                        if post.videoURL != nil || post.effectiveIsVideo || post.isYouTubeVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.8))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if post.galleryItems.count > 1 {
                            GalleryDotIndicator(count: post.galleryItems.count)
                                .allowsHitTesting(false)
                        }
                    }
                }

                Button {
                    performTap(.showDetail)
                } label: {
                    let vote = engagement.vote(for: "t3_\(post.id)", loaded: post.initialVote)
                    let voteColor = vote > 0 ? Theme.primary : vote < 0 ? Theme.downvote : Theme.textSecondary
                    HStack(spacing: 6) {
                        Image(systemName: vote < 0 ? "arrow.down" : "arrow.up")
                            .font(.caption)
                            .foregroundStyle(voteColor)
                        Text(Formatters.score(post.displayScore(vote: vote)))
                            .font(.subheadline)
                            .foregroundStyle(voteColor)
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                        Text("\(Formatters.score(post.numComments)) comments")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let horizontalOffset = interaction.updateDrag(
                            translation: value.translation
                        )
                        tapSuppressionResetTask?.cancel()
                        guard let horizontalOffset else { return }
                        offset = horizontalOffset
                    }
                    .onEnded { value in
                        let action = interaction.endDrag(
                            translation: value.translation,
                            canHide: onHide != nil
                        )
                        scheduleTapSuppressionReset()

                        switch action {
                        case .openReddit:
                            withAnimation(.spring()) { offset = 0 }
                            openURL(post.redditURL)
                        case .hide:
                            withAnimation(.easeIn(duration: 0.2)) {
                                offset = -swipeHideOffset
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(0.2))
                                withAnimation(.easeOut(duration: 0.25)) {
                                    collapsing = true
                                }
                                try? await Task.sleep(for: .seconds(0.25))
                                onHide?(post.id)
                                // The lazy feed keeps this card's state for its post ID, so a post restored
                                // by Undo or a failed hide would otherwise come back collapsed and invisible.
                                collapsing = false
                                offset = 0
                            }
                        case .reset:
                            withAnimation(.spring()) { offset = 0 }
                        case nil:
                            break
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(height: collapsing ? 0 : nil)
        .clipped()
        .opacity(collapsing ? 0 : 1)
        .sensoryFeedback(trigger: swipeAction) { _, action in
            action == .reset ? nil : .selection
        }
    }

    private var swipeAction: PostCardSwipeAction {
        PostCardInteractionState.swipeAction(forOffset: offset, canHide: onHide != nil)
    }

    // Gray until the swipe passes the action threshold, then the action's color, icon, and label.
    private var swipeBackground: some View {
        let revealsTrailingEdge = offset < 0
        let isArmed = swipeAction != .reset
        return ZStack(alignment: revealsTrailingEdge ? .trailing : .leading) {
            Rectangle()
                .fill(isArmed ? (revealsTrailingEdge ? Theme.swipeHide : Theme.swipeOpen) : Theme.surfaceElevated)
            HStack(spacing: 6) {
                Image(systemName: revealsTrailingEdge ? hideSystemImage : "safari")
                if isArmed {
                    Text(revealsTrailingEdge ? hideLabel : "Open")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isArmed ? .white : Theme.textMuted)
            .padding(.horizontal, 24)
        }
        .accessibilityHidden(true)
    }

    private func performTap(_ requestedAction: PostCardTapAction) {
        guard let action = interaction.acceptedTapAction(requestedAction) else { return }

        switch action {
        case .showDetail:
            onShowDetail?()
        case .showSubreddit:
            onShowSubreddit?()
        case .showMedia:
            if post.galleryItems.count > 1 {
                onShowGallery?()
            } else {
                onShowDetail?()
            }
        case .openExternalURL(let url):
            openURL(url)
        }
    }

    private func scheduleTapSuppressionReset() {
        tapSuppressionResetTask?.cancel()
        guard interaction.suppressesTapActions else { return }
        let suppressionGeneration = interaction.suppressionGeneration

        tapSuppressionResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            interaction.resetTapSuppression(ifGeneration: suppressionGeneration)
            tapSuppressionResetTask = nil
        }
    }
}

enum PostCardTapAction: Equatable {
    case showDetail
    case showSubreddit
    case showMedia
    case openExternalURL(URL)
}

enum PostCardSwipeAction: Equatable {
    case openReddit
    case hide
    case reset
}

struct PostCardInteractionState: Equatable {
    private enum DragAxis: Equatable {
        case horizontal
        case vertical
    }

    private(set) var suppressesTapActions = false
    private(set) var suppressionGeneration: UInt = 0
    private var dragAxis: DragAxis?

    mutating func updateDrag(translation: CGSize) -> CGFloat? {
        if dragAxis == nil {
            suppressionGeneration &+= 1
        }
        let resolvedAxis = dragAxis ?? Self.axis(for: translation)
        dragAxis = resolvedAxis
        suppressesTapActions = true
        guard resolvedAxis == .horizontal else { return nil }

        return translation.width
    }

    mutating func endDrag(
        translation: CGSize,
        canHide: Bool
    ) -> PostCardSwipeAction? {
        if dragAxis == nil {
            suppressionGeneration &+= 1
        }
        let resolvedAxis = dragAxis ?? Self.axis(for: translation)
        dragAxis = nil
        suppressesTapActions = true
        guard resolvedAxis == .horizontal else { return nil }
        return Self.swipeAction(forOffset: translation.width, canHide: canHide)
    }

    // The action a release at this horizontal offset performs; the card also uses it to arm its swipe feedback.
    static func swipeAction(forOffset offset: CGFloat, canHide: Bool) -> PostCardSwipeAction {
        if offset > swipeThreshold {
            return .openReddit
        }
        if offset < -swipeThreshold, canHide {
            return .hide
        }
        return .reset
    }

    func acceptedTapAction(_ action: PostCardTapAction) -> PostCardTapAction? {
        suppressesTapActions ? nil : action
    }

    @discardableResult
    mutating func resetTapSuppression(ifGeneration generation: UInt) -> Bool {
        guard generation == suppressionGeneration else { return false }
        suppressesTapActions = false
        return true
    }

    private static let swipeThreshold: CGFloat = 100

    private static func axis(for translation: CGSize) -> DragAxis {
        abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
    }
}
