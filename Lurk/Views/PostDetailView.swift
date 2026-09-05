import AVKit
import SwiftUI
import UIKit

struct PostDetailView: View {
    let post: Post
    var removeAction: PostRemoveAction? = nil
    var commentsFetch: CommentLoadStore.Fetch? = nil
    var continueThreadAction: ((URL) -> Void)? = nil

    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @State private var player: AVPlayer?
    @State private var playerPostID: String = ""
    @State private var playerObservers = PlayerObservers()
    @State private var playbackID = UUID()
    @State private var suspensionPlaybackID = UUID()
    @State private var animatedMediaRefreshID = UUID()
    @State private var ordinaryVideoIsVisible = false
    @State private var detailMediaSuspended = false
    @State private var commentStore = CommentLoadStore()
    @State private var commentLoadAttempt = 0
    @State private var showCommentSheet = false
    @State private var showSubreddit = false
    @State private var mediaSaved = false
    @State private var savingMedia = false
    @State private var mediaSaveTask: Task<Void, Never>?
    @State private var mediaSaveTaskID: UUID?
    @State private var showMediaViewer = false
    @State private var showShareSheet = false
    @State private var removingPost = false
    @State private var removeError: String?
    @State private var safariDestination: SafariDestination?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(post.subredditNamePrefixed)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .onTapGesture { presentSubreddit() }
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                        Text(Formatters.timeAgo(post.createdUtc))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        Text("u/\(post.author)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(post.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)

                    if let crosspost = post.crosspost {
                        if let originalURL = crosspost.originalURL {
                            Button {
                                openURL(originalURL)
                            } label: {
                                CrosspostAttributionLabel(crosspost: crosspost)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the original post in your browser")
                        } else {
                            CrosspostAttributionLabel(crosspost: crosspost)
                        }
                        if let originalTitle = crosspost.title, originalTitle != post.title {
                            Text(originalTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if let videoURL = post.videoURL {
                        if post.loopsVideo {
                            InlineLoopingVideoView(
                                url: videoURL,
                                posterURL: post.imageURL,
                                aspectRatio: post.videoAspectRatio ?? post.imageAspectRatio,
                                activation: .whenVisible
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) { mediaExpandButton }
                        } else {
                            AVKitPlayerView(player: player)
                                .aspectRatio(post.videoAspectRatio ?? 16/9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) { mediaExpandButton }
                                .overlay {
                                    if playerObservers.failed {
                                        VStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle")
                                                .font(.title2)
                                                .foregroundStyle(.white.opacity(0.9))
                                            Text("Playback failed")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                        .padding(12)
                                        .background(.black.opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                                    ordinaryVideoIsVisible = isVisible
                                    if isVisible, !detailMediaSuspended {
                                        setupPlayer(for: videoURL)
                                    } else {
                                        teardownPlayer()
                                    }
                                }
                                .onDisappear { teardownPlayer() }
                        }
                    } else if let youtubeVideoID = post.youtubeVideoID {
                        YouTubePlayerView(videoID: youtubeVideoID)
                            .aspectRatio(post.imageAspectRatio ?? 16/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let animatedImageURL = post.animatedImageURL {
                        AnimatedGIFView(
                            url: animatedImageURL,
                            posterURL: post.imageURL,
                            limits: .inline,
                            activation: .whenVisible,
                            onMediaTap: presentMediaViewer
                        )
                            .id(animatedMediaRefreshID)
                            .aspectRatio(post.imageAspectRatio ?? 16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if post.effectiveIsVideo {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.surfaceElevated)
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "video.slash")
                                        .font(.largeTitle)
                                        .foregroundStyle(Theme.textMuted)
                                    Text("Video unavailable")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                    } else if let imageURL = post.imageURL {
                        PostImagePreviewView(post: post, imageURL: imageURL) {
                            presentMediaViewer()
                        }
                    }

                    if !post.selftext.isEmpty {
                        CommentBodyView(content: post.selftext, textFont: .body)
                    }

                    if !post.crosspostBody.isEmpty, post.crosspostBody != post.selftext {
                        CommentBodyView(content: post.crosspostBody, textFont: .body)
                    }

                    if post.crosspost != nil, post.imageURL == nil,
                       let externalURL = post.externalLinkURL,
                       let domain = post.externalLinkDomain {
                        Link(destination: externalURL) {
                            Label("Open \(domain)", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.swipeOpen)
                                .frame(minHeight: 44)
                        }
                    }

                    HStack(spacing: 16) {
                        VoteControlsView(thingID: "t3_\(post.id)", initialScore: post.score)

                        Label(Formatters.score(post.numComments), systemImage: "bubble.right")
                            .foregroundStyle(Theme.textSecondary)

                        Spacer()

                        if !post.downloadableVideoURLs.isEmpty
                            || ((post.animatedImageURL ?? post.imageURL) != nil && !post.isYouTubeVideo) {
                            Button {
                                cancelMediaSaveTask()
                                let operationID = UUID()
                                mediaSaveTaskID = operationID
                                mediaSaved = false
                                savingMedia = true
                                mediaSaveTask = Task { @MainActor in
                                    defer {
                                        if mediaSaveTaskID == operationID {
                                            mediaSaveTask = nil
                                            mediaSaveTaskID = nil
                                        }
                                    }
                                    guard mediaSaveTaskID == operationID, !Task.isCancelled else { return }
                                    let result: MediaSaver.SaveResult
                                    let videoURLs = post.downloadableVideoURLs
                                    if !videoURLs.isEmpty {
                                        result = await MediaSaver.saveVideo(from: videoURLs)
                                    } else if let animatedImageURL = post.animatedImageURL {
                                        result = await MediaSaver.saveImageData(from: animatedImageURL)
                                    } else if let imageURL = post.imageURL {
                                        result = await MediaSaver.saveImage(from: imageURL)
                                    } else {
                                        result = .failed
                                    }
                                    guard mediaSaveTaskID == operationID, !Task.isCancelled else { return }
                                    savingMedia = false
                                    if result == .saved {
                                        mediaSaved = true
                                        do {
                                            try await Task.sleep(for: .seconds(1.5))
                                        } catch {
                                            return
                                        }
                                        guard mediaSaveTaskID == operationID, !Task.isCancelled else { return }
                                        mediaSaved = false
                                    }
                                }
                            } label: {
                                Group {
                                    if savingMedia {
                                        ProgressView().tint(Theme.textSecondary)
                                    } else if mediaSaved {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                }
                                .foregroundStyle(mediaSaved ? Theme.primary : Theme.textSecondary)
                            }
                            .disabled(savingMedia)
                            .padding(.trailing, 8)
                        }

                        Button {
                            presentShareSheet()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .font(.subheadline)

                    if session.isLoggedIn {
                        Button {
                            presentCommentSheet()
                        } label: {
                            Label("Comment", systemImage: "square.and.pencil")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Divider().background(Theme.border)
                    commentSection
                }
                .padding(16)
            }
            .background(Theme.background)
            .defaultScrollAnchor(.top)
            .task(id: commentLoadAttempt) {
                await commentStore.load {
                    if let commentsFetch {
                        return try await commentsFetch()
                    }
                    return try await client.fetchComments(permalink: post.permalink)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        commentStore.cancel()
                        cancelMediaSaveTask()
                        teardownPlayer()
                        dismiss()
                    }
                    .foregroundStyle(Theme.primary)
                }
                if let action = removeAction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await performRemoveAction(action) }
                        } label: {
                            if removingPost {
                                ProgressView().tint(Theme.primary)
                            } else {
                                Text(action.label)
                            }
                        }
                        .foregroundStyle(Theme.primary)
                        .disabled(removingPost)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            commentStore.cancel()
            cancelMediaSaveTask()
        }
        .fullScreenCover(isPresented: $showSubreddit, onDismiss: detailCoverDismissed) {
            SubredditCoverView(subreddit: post.subreddit, title: post.subredditNamePrefixed) {
                showSubreddit = false
            }
        }
        .sheet(isPresented: $showCommentSheet, onDismiss: resumeAfterPresentation) {
            ComposeReplySheet(thingID: "t3_\(post.id)", isPresented: $showCommentSheet)
        }
        .sheet(item: $safariDestination, onDismiss: resumeAfterPresentation) { destination in
            SafariView(url: destination.url) { safariDestination = nil }
        }
        .fullScreenCover(isPresented: $showMediaViewer, onDismiss: mediaViewerDismissed) {
            if let videoURL = post.videoURL {
                VideoViewerView(
                    url: videoURL,
                    aspectRatio: post.videoAspectRatio,
                    downloadURLs: post.downloadableVideoURLs,
                    loops: post.loopsVideo
                )
            } else if post.isGallery && !post.galleryItems.isEmpty {
                GalleryViewerView(items: post.galleryItems)
            } else if let animatedImageURL = post.animatedImageURL {
                GalleryViewerView(items: [
                    GalleryMedia(
                        id: 0,
                        url: animatedImageURL,
                        isAnimated: true,
                        posterURL: post.imageURL
                    ),
                ])
            } else if let imageURL = post.imageURL {
                GalleryViewerView(items: [GalleryMedia(id: 0, url: imageURL, isAnimated: false)])
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: resumeAfterPresentation) {
            PostShareSheet(url: post.redditURL, title: post.title, imageURL: post.imageURL)
        }
        .alert("Reddit action failed", isPresented: removeErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removeError ?? "")
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(Theme.text)

            switch commentStore.state {
            case .idle, .loading:
                ProgressView("Loading comments…")
                    .tint(Theme.primary)
                    .foregroundStyle(Theme.textSecondary)
            case .failed(let message):
                Text("Couldn’t load comments")
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Retry") { commentLoadAttempt += 1 }
                    .foregroundStyle(Theme.primary)
                    .accessibilityLabel("Retry loading comments")
            case .loaded:
                if commentStore.comments.isEmpty {
                    Text("No comments to show.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(commentStore.comments) { comment in
                            CommentRowView(
                                comment: comment,
                                postPermalink: post.permalink,
                                onContinueThread: { url in
                                    if let continueThreadAction {
                                        continueThreadAction(url)
                                    } else {
                                        suspendDetailMedia()
                                        safariDestination = SafariDestination(url: url)
                                    }
                                },
                                onPresentReply: suspendDetailMedia,
                                onDismissReply: resumeAfterPresentation
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var removeErrorPresented: Binding<Bool> {
        Binding(
            get: { removeError != nil },
            set: { if !$0 { removeError = nil } }
        )
    }

    private var mediaExpandButton: some View {
        Button { presentMediaViewer() } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .padding(8)
        .accessibilityLabel("Open media viewer")
    }

    private func performRemoveAction(_ action: PostRemoveAction) async {
        guard !removingPost else { return }
        guard session.isLoggedIn else {
            removeError = "Log in to Reddit to \(action.label.lowercased()) this post."
            return
        }

        removingPost = true
        defer { removingPost = false }

        do {
            let postId = post.id
            let request = session.authenticatedRequest(
                url: action.apiURL,
                formData: ["id": "t3_\(postId)"]
            )
            try await client.execute(request)
            action.onComplete?(postId)
            commentStore.cancel()
            cancelMediaSaveTask()
            teardownPlayer()
            dismiss()
        } catch {
            removeError = error.localizedDescription
        }
    }

    private func setupPlayer(for url: URL) {
        playbackStore.activate(playbackID)
        if player == nil || playerPostID != post.id {
            playerObservers.reset()
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            playerPostID = post.id
            if let item = newPlayer.currentItem {
                playerObservers.observe(item: item, player: newPlayer, loops: post.loopsVideo)
            }
        }
        player?.play()
    }

    private func teardownPlayer() {
        playerObservers.reset()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerPostID = ""
        playbackStore.deactivate(playbackID)
    }

    private func cancelMediaSaveTask() {
        mediaSaveTask?.cancel()
        mediaSaveTask = nil
        mediaSaveTaskID = nil
        mediaSaved = false
        savingMedia = false
    }

    private func presentMediaViewer() {
        suspendDetailMedia()
        showMediaViewer = true
    }

    private func mediaViewerDismissed() {
        resumeAfterPresentation()
    }

    private func presentSubreddit() {
        suspendDetailMedia()
        showSubreddit = true
    }

    private func detailCoverDismissed() {
        resumeAfterPresentation()
    }

    private func presentCommentSheet() {
        suspendDetailMedia()
        showCommentSheet = true
    }

    private func presentShareSheet() {
        suspendDetailMedia()
        showShareSheet = true
    }

    private func suspendDetailMedia() {
        detailMediaSuspended = true
        teardownPlayer()
        playbackStore.activate(suspensionPlaybackID)
    }

    private func resumeAfterPresentation() {
        playbackStore.deactivate(suspensionPlaybackID)
        detailMediaSuspended = false
        resumeDetailMedia()
    }

    private func resumeDetailMedia() {
        if ordinaryVideoIsVisible,
           let videoURL = post.videoURL,
           !post.loopsVideo {
            setupPlayer(for: videoURL)
        } else if post.animatedImageURL != nil {
            animatedMediaRefreshID = UUID()
        }
    }
}

@Observable
final class PlayerObservers {
    var failed = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    func observe(item: AVPlayerItem, player: AVPlayer, loops: Bool) {
        let failHandler: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor [weak self] in self?.failed = true }
        }
        let errorLogHandler: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor [weak self, weak item] in
                guard let item, item.error != nil else { return }
                self?.failed = true
            }
        }
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item,
                queue: .main,
                using: failHandler
            )
        )
        if loops {
            let loopController = PlayerLoopController(player: player)
            let loopHandler: @Sendable (Notification) -> Void = { _ in
                Task { @MainActor in
                    loopController.restart()
                }
            }
            tokens.append(
                NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main,
                    using: loopHandler
                )
            )
        }
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.newErrorLogEntryNotification,
                object: item,
                queue: .main,
                using: errorLogHandler
            )
        )
    }

    func reset() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
        failed = false
    }

    deinit { reset() }
}

@MainActor
final class PlayerLoopController {
    weak var player: AVPlayer?

    init(player: AVPlayer) {
        self.player = player
    }

    func restart() {
        player?.seek(to: .zero)
        player?.play()
    }
}

private struct PostImagePreviewView: View {
    let post: Post
    let imageURL: URL
    let showMediaViewer: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let externalURL = post.externalLinkURL, let domain = post.externalLinkDomain {
            VStack(spacing: 0) {
                imageContent
                    .contentShape(Rectangle())
                    .onTapGesture { openURL(externalURL) }

                HStack(spacing: 12) {
                    Text(domain)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        openURL(externalURL)
                    } label: {
                        Text("Open")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .overlay {
                                Capsule()
                                    .stroke(Theme.textSecondary, lineWidth: 1)
                            }
                    }
                }
                .padding(12)
                .background(Theme.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            }
        } else {
            imageContent
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { showMediaViewer() }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                EmptyView()
            default:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated)
                    .aspectRatio(post.imageAspectRatio ?? 16/9, contentMode: .fit)
                    .overlay { ProgressView().tint(Theme.textMuted) }
            }
        }
        .overlay(alignment: .bottom) {
            if post.galleryItems.count > 1 {
                GalleryDotIndicator(count: post.galleryItems.count)
            }
        }
    }
}

struct CommentRowView: View {
    let comment: Comment
    let postPermalink: String
    let onContinueThread: (URL) -> Void
    var onPresentReply: () -> Void = {}
    var onDismissReply: () -> Void = {}
    @Environment(RedditSession.self) private var session
    @State private var collapsed = false
    @State private var selecting = false
    @State private var showReplySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: handleNonInteractiveTap) {
                HStack(spacing: 6) {
                    Text("u/\(comment.author)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    if comment.isSubmitter {
                        Text("OP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.opBadge)
                    }
                    Text(Formatters.timeAgo(comment.createdUtc))
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsed ? "Expand comment by \(comment.author)" : "Collapse comment by \(comment.author)")
            if !collapsed {
                CommentBodyView(
                    content: comment.body,
                    nonInteractiveTapAction: CommentBodyTapAction(
                        perform: handleNonInteractiveTap,
                        mediaAccessibility: MediaActionAccessibility(
                            label: "Collapse comment by \(comment.author)",
                            hint: "Double-tap to collapse this comment."
                        )
                    ),
                    onNonInteractiveLongPress: beginSelecting,
                    isSelecting: selecting
                )

                HStack(spacing: 12) {
                    VoteControlsView(thingID: "t1_\(comment.id)", initialScore: comment.score, inactiveColor: Theme.textMuted)

                    if session.isLoggedIn {
                        Button {
                            onPresentReply()
                            showReplySheet = true
                        } label: {
                            Label("Reply", systemImage: "bubble.left")
                                .foregroundStyle(Theme.textMuted)
                        }
                    } else {
                        Label("Reply", systemImage: "bubble.left")
                            .foregroundStyle(Theme.textMuted)
                    }

                    Spacer()
                }
                .font(.caption)
                .padding(.top, 4)

                if !comment.replies.isEmpty {
                    ForEach(comment.replies) { reply in
                        CommentRowView(
                            comment: reply,
                            postPermalink: postPermalink,
                            onContinueThread: onContinueThread,
                            onPresentReply: onPresentReply,
                            onDismissReply: onDismissReply
                        )
                            .padding(.leading, 16)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Theme.border)
                                    .frame(width: 2)
                                    .padding(.leading, 4)
                            }
                    }
                }

                if comment.hasMoreReplies,
                   let url = comment.continuationURL(postPermalink: postPermalink) {
                    Button {
                        onContinueThread(url)
                    } label: {
                        Label("Continue thread in Safari", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.primary)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this comment and its replies in Safari")
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showReplySheet, onDismiss: onDismissReply) {
            ComposeReplySheet(thingID: "t1_\(comment.id)", isPresented: $showReplySheet)
        }
    }

    private func handleNonInteractiveTap() {
        if selecting {
            withAnimation(.easeInOut(duration: 0.2)) { selecting = false }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
        }
    }

    private func beginSelecting() {
        guard !collapsed else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selecting = true }
    }
}

struct CommentBodyTapAction {
    let perform: () -> Void
    let mediaAccessibility: MediaActionAccessibility
}

struct CommentBodyView: View {
    let content: String
    var textFont: Font = .subheadline
    var nonInteractiveTapAction: CommentBodyTapAction? = nil
    var onNonInteractiveLongPress: (() -> Void)? = nil
    var isSelecting = false
    @State private var revealedSpoilers: Set<Int> = []
    @State private var revealedContent: String?
    @Environment(\.openURL) private var openURL

    // Matches in priority order: giphy embeds, markdown links, image URLs, plain URLs
    private static let tokenPattern = try! NSRegularExpression(
        pattern: """
        !\\[gif\\]\\(giphy\\|([^)]+)\\)\
        |\\[([^\\]]+)\\]\\((https?://[^)]+)\\)\
        |https?://[^\\s)\"]+\\.(?:jpg|jpeg|png|gif|webp)(?:[^\\s)\"]*)\
        |https?://[^\\s)\"]+
        """,
        options: [.caseInsensitive, .allowCommentsAndWhitespace]
    )

    private static let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]

    var body: some View {
        Group {
            if isSelecting {
                SelectableTextView(text: CommentSpoilers.selectionText(from: content, revealed: activeRevealedSpoilers))
            } else {
                renderedBody
            }
        }
    }

    private var activeRevealedSpoilers: Set<Int> {
        revealedContent == content ? revealedSpoilers : []
    }

    private var renderedBody: some View {
        let parts = Self.displayParts(from: content, revealedSpoilers: activeRevealedSpoilers)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        nonInteractiveTextTarget {
                            VStack(alignment: .leading, spacing: 2) {
                                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                                let groups = Self.groupLines(lines)
                                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                    switch group {
                                    case .line(let line):
                                        renderLine(line)
                                    case .quote(let qlines):
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(Array(qlines.enumerated()), id: \.offset) { _, ql in
                                                renderLine(ql)
                                            }
                                        }
                                        .padding(.leading, 10)
                                        .overlay(alignment: .leading) {
                                            Rectangle()
                                                .fill(Theme.primary)
                                                .frame(width: 3)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .spoiler(let id, _):
                    Button {
                        if revealedContent != content {
                            revealedContent = content
                            revealedSpoilers = []
                        }
                        revealedSpoilers.insert(id)
                    } label: {
                        Label("Reveal spoiler", systemImage: "eye.slash")
                            .font(textFont)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reveal spoiler")
                    .accessibilityHint("Double-tap to reveal hidden content.")
                case .image(let url):
                    nonInteractiveMediaTarget {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                EmptyView()
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.surfaceElevated)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .overlay { ProgressView().tint(Theme.textMuted) }
                            }
                        }
                    }
                case .gif(let url):
                    AnimatedGIFView(
                        url: url,
                        onMediaTap: nonInteractiveTapAction?.perform,
                        onMediaLongPress: onNonInteractiveLongPress,
                        mediaActionAccessibility: nonInteractiveTapAction?.mediaAccessibility ?? .openGIF
                    )
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .link(let title, let url):
                    Button {
                        openURL(url)
                    } label: {
                        Text(title)
                            .font(textFont)
                            .foregroundStyle(Theme.primary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func nonInteractiveTextTarget<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let nonInteractiveTapAction, let onNonInteractiveLongPress {
            content()
                .contentShape(Rectangle())
                .onTapGesture(perform: nonInteractiveTapAction.perform)
                .onLongPressGesture(perform: onNonInteractiveLongPress)
        } else if let nonInteractiveTapAction {
            content()
                .contentShape(Rectangle())
                .onTapGesture(perform: nonInteractiveTapAction.perform)
        } else if let onNonInteractiveLongPress {
            content()
                .contentShape(Rectangle())
                .onLongPressGesture(perform: onNonInteractiveLongPress)
        } else {
            content()
        }
    }

    @ViewBuilder
    private func nonInteractiveMediaTarget<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let nonInteractiveTapAction, let onNonInteractiveLongPress {
            content()
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture()
                        .exclusively(before: TapGesture())
                        .onEnded { value in
                            switch value {
                            case .first:
                                onNonInteractiveLongPress()
                            case .second:
                                nonInteractiveTapAction.perform()
                            }
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nonInteractiveTapAction.mediaAccessibility.label)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(nonInteractiveTapAction.mediaAccessibility.hint)
                .accessibilityAction { nonInteractiveTapAction.perform() }
                .accessibilityAction(named: Text("Select comment text")) {
                    onNonInteractiveLongPress()
                }
        } else if let nonInteractiveTapAction {
            Button(action: nonInteractiveTapAction.perform) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nonInteractiveTapAction.mediaAccessibility.label)
            .accessibilityHint(nonInteractiveTapAction.mediaAccessibility.hint)
        } else if let onNonInteractiveLongPress {
            content()
                .contentShape(Rectangle())
                .onLongPressGesture(perform: onNonInteractiveLongPress)
                .accessibilityAction(named: Text("Select comment text")) {
                    onNonInteractiveLongPress()
                }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 8)
        } else if Self.isHorizontalRule(trimmed) {
            Divider().background(Theme.border).padding(.vertical, 4)
        } else if let attr = Self.markdownString(Self.cleanLine(trimmed)) {
            Text(attr)
                .font(textFont)
                .foregroundStyle(Theme.text)
        }
    }

    enum BodyPart {
        case text(String)
        case spoiler(Int, String)
        case image(URL)
        case gif(URL)
        case link(String, URL)
    }

    private enum LineGroup {
        case line(String)
        case quote([String])
    }

    private static func groupLines(_ lines: [String]) -> [LineGroup] {
        var groups: [LineGroup] = []
        var quoteBuffer: [String] = []
        func flush() {
            if !quoteBuffer.isEmpty {
                groups.append(.quote(quoteBuffer))
                quoteBuffer.removeAll()
            }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var normalized = trimmed
            while normalized.hasPrefix(">") { normalized.removeFirst() }
            if trimmed.hasPrefix(">") && !normalized.hasPrefix("!") {
                var body = normalized
                if body.hasPrefix(" ") { body.removeFirst() }
                quoteBuffer.append(body)
            } else {
                flush()
                groups.append(.line(line))
            }
        }
        flush()
        return groups
    }

    static func parse(_ text: String, revealedSpoilers: Set<Int> = []) -> [BodyPart] {
        guard !text.isEmpty else { return [.text(text)] }
        var parts: [BodyPart] = []
        var visibleText = ""
        for part in CommentSpoilers.parse(text) {
            switch part {
            case .text(let text):
                visibleText += text
            case .spoiler(let id, let content):
                if revealedSpoilers.contains(id) {
                    visibleText += content
                } else {
                    if !visibleText.isEmpty {
                        parts += parseVisibleText(visibleText)
                        visibleText = ""
                    }
                    parts.append(.spoiler(id, content))
                }
            }
        }
        if !visibleText.isEmpty {
            parts += parseVisibleText(visibleText)
        }
        return parts
    }

    private static func parseVisibleText(_ text: String) -> [BodyPart] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = tokenPattern.matches(in: text, range: fullRange)

        guard !matches.isEmpty else { return [.text(text)] }

        var parts: [BodyPart] = []
        var lastEnd = 0

        for match in matches {
            let range = match.range
            if range.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
                parts.append(.text(before))
            }

            let full = nsText.substring(with: range)

            if match.range(at: 1).location != NSNotFound {
                // Giphy: ![gif](giphy|ID) or ![gif](giphy|ID|variant)
                let giphyParts = nsText.substring(with: match.range(at: 1)).components(separatedBy: "|")
                let giphyID = giphyParts.first ?? ""
                if let url = URL(string: "https://media.giphy.com/media/\(giphyID)/giphy.gif") {
                    parts.append(.gif(url))
                }
            } else if match.range(at: 2).location != NSNotFound {
                // Markdown link: [text](url)
                let linkText = nsText.substring(with: match.range(at: 2))
                let urlStr = nsText.substring(with: match.range(at: 3))
                if let url = URL(string: urlStr) {
                    if isGIFURL(url) {
                        parts.append(.gif(url))
                    } else if isImageURL(url) {
                        parts.append(.image(url))
                    } else {
                        parts.append(.link(linkText, url))
                    }
                }
            } else {
                let (urlString, trailingText) = splitTrailingPunctuation(from: full)
                if let url = URL(string: urlString), isGIFURL(url) {
                    parts.append(.gif(url))
                } else if let url = URL(string: urlString), isImageURL(url) {
                    parts.append(.image(url))
                } else if let url = URL(string: urlString) {
                    let display = urlString
                        .replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                    parts.append(.link(display, url))
                } else {
                    parts.append(.text(urlString))
                }
                if !trailingText.isEmpty {
                    parts.append(.text(trailingText))
                }
            }

            lastEnd = range.location + range.length
        }

        if lastEnd < nsText.length {
            parts.append(.text(nsText.substring(from: lastEnd)))
        }

        return parts
    }

    static func displayParts(from text: String, revealedSpoilers: Set<Int> = []) -> [BodyPart] {
        var inlineGIFCount = 0
        return parse(text, revealedSpoilers: revealedSpoilers).map { part in
            guard case .gif(let url) = part else { return part }
            defer { inlineGIFCount += 1 }
            return inlineGIFCount == 0 ? part : .link("Open GIF", url)
        }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isGIFURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("gif") == .orderedSame
    }

    private static func splitTrailingPunctuation(from token: String) -> (String, String) {
        var urlString = token
        var trailingText = ""
        let punctuation = CharacterSet.punctuationCharacters
        let preservedURLCharacters = CharacterSet(charactersIn: "/-_~%+=&#@$*")

        while let scalar = urlString.unicodeScalars.last,
              punctuation.contains(scalar),
              !preservedURLCharacters.contains(scalar),
              !isIPv6AuthorityClosingBracket(scalar, in: urlString) {
            let character = urlString.removeLast()
            trailingText.insert(character, at: trailingText.startIndex)
        }
        return (urlString, trailingText)
    }

    private static func isIPv6AuthorityClosingBracket(
        _ scalar: UnicodeScalar,
        in urlString: String
    ) -> Bool {
        guard scalar == "]",
              let url = URL(string: urlString),
              url.path.isEmpty,
              url.host?.contains(":") == true else {
            return false
        }
        return true
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy({ $0 == "-" })
            || stripped.allSatisfy({ $0 == "*" })
            || stripped.allSatisfy({ $0 == "_" })
    }

    private static func cleanLine(_ line: String) -> String {
        var result = line
        if result.hasPrefix("#") {
            let stripped = result.drop(while: { $0 == "#" })
            if stripped.first == " " {
                result = String(stripped.dropFirst())
            }
        }
        return result
    }

    private static func markdownString(_ text: String) -> AttributedString? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(trimmed)
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .subheadline)
        textView.textColor = UIColor(Theme.text)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.text = text
    }
}

struct VoteControlsView: View {
    let thingID: String
    var inactiveColor: Color = Theme.textSecondary

    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client

    @State private var voted: Int = 0
    @State private var displayScore: Int
    @State private var voteError: String?

    init(thingID: String, initialScore: Int, inactiveColor: Color = Theme.textSecondary) {
        self.thingID = thingID
        self.inactiveColor = inactiveColor
        _displayScore = State(initialValue: initialScore)
    }

    var body: some View {
        HStack(spacing: session.isLoggedIn ? 8 : 6) {
            if session.isLoggedIn {
                Button {
                    let newDir = voted == 1 ? 0 : 1
                    submitVote(newDir)
                } label: {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(voted == 1 ? Theme.primary : inactiveColor)
                }
            } else {
                Image(systemName: "arrow.up")
                    .foregroundStyle(inactiveColor)
            }

            Text(Formatters.score(displayScore))
                .foregroundStyle(voted == 1 ? Theme.primary : voted == -1 ? Theme.downvote : Theme.textSecondary)

            if session.isLoggedIn {
                Button {
                    let newDir = voted == -1 ? 0 : -1
                    submitVote(newDir)
                } label: {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(voted == -1 ? Theme.downvote : inactiveColor)
                }
            } else {
                Image(systemName: "arrow.down")
                    .foregroundStyle(inactiveColor)
            }
        }
        .alert("Reddit action failed", isPresented: voteErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voteError ?? "")
        }
    }

    private var voteErrorPresented: Binding<Bool> {
        Binding(
            get: { voteError != nil },
            set: { if !$0 { voteError = nil } }
        )
    }

    private func submitVote(_ newDir: Int) {
        let previousVote = voted
        let previousScore = displayScore
        voteError = nil
        voted = newDir
        displayScore += newDir - previousVote

        Task { @MainActor in
            do {
                let request = session.authenticatedRequest(
                    url: RedditAPI.vote,
                    formData: ["id": thingID, "dir": "\(newDir)"]
                )
                try await client.execute(request)
            } catch {
                guard voted == newDir else { return }
                voted = previousVote
                displayScore = previousScore
                voteError = error.localizedDescription
            }
        }
    }
}

struct ComposeReplySheet: View {
    let thingID: String
    @Binding var isPresented: Bool
    @Environment(RedditSession.self) private var session
    @Environment(\.redditClient) private var client
    @State private var text = ""
    @State private var posting = false
    @State private var postError: String?

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                if let postError {
                    Text(postError)
                        .font(.caption)
                        .foregroundStyle(Theme.swipeHide)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                Spacer()
            }
            .background(Theme.background)
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(Theme.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await postReply() }
                    } label: {
                        if posting {
                            ProgressView().tint(Theme.primary)
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(Theme.primary)
                    .disabled(isEmpty || posting)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onChange(of: text) { _, _ in
            postError = nil
        }
    }

    private func postReply() async {
        guard !isEmpty, !posting else { return }
        postError = nil
        guard session.isLoggedIn else {
            postError = "Log in to Reddit to post a reply."
            return
        }
        posting = true
        defer { posting = false }

        do {
            let request = session.authenticatedRequest(
                url: RedditAPI.comment,
                formData: [
                    "thing_id": thingID,
                    "text": text
                ]
            )
            try await client.execute(request)
            text = ""
            isPresented = false
        } catch {
            postError = error.localizedDescription
        }
    }
}
