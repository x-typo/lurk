import AVKit
import SwiftUI
import UIKit

struct PostDetailView: View {
    let post: Post
    let session: RedditSession
    let client: RedditClient
    let filterStore: PostFilterStore
    let subStore: SubredditStore
    let blockStore: BlockedSubredditStore
    var removeAction: PostRemoveAction? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var comments: [Comment] = []
    @State private var showCommentSheet = false
    @State private var showSubreddit = false
    @State private var mediaSaved = false
    @State private var savingMedia = false
    @State private var showMediaViewer = false
    @State private var showShareSheet = false

    init(post: Post, session: RedditSession, client: RedditClient, filterStore: PostFilterStore, subStore: SubredditStore, blockStore: BlockedSubredditStore, removeAction: PostRemoveAction? = nil) {
        self.post = post
        self.session = session
        self.client = client
        self.filterStore = filterStore
        self.subStore = subStore
        self.blockStore = blockStore
        self.removeAction = removeAction
        _player = State(initialValue: post.videoURL.map { AVPlayer(url: $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(post.subredditNamePrefixed)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .onTapGesture { showSubreddit = true }
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

                    if let player {
                        AVKitPlayerView(player: player)
                            .aspectRatio(post.videoAspectRatio ?? 16/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button { showMediaViewer = true } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(8)
                            }
                            .onAppear { player.play() }
                            .onDisappear { player.pause() }
                    } else if let imageURL = post.imageURL {
                        AsyncImage(url: imageURL) { phase in
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
                        .overlay(alignment: .bottom) {
                            if post.galleryItems.count > 1 {
                                GalleryDotIndicator(count: post.galleryItems.count)
                            }
                        }
                        .onTapGesture { showMediaViewer = true }
                    }

                    if !post.selftext.isEmpty {
                        CommentBodyView(content: post.selftext, textFont: .body)
                    }

                    HStack(spacing: 16) {
                        VoteControlsView(thingID: "t3_\(post.id)", initialScore: post.score, session: session, client: client)

                        Label(Formatters.score(post.numComments), systemImage: "bubble.right")
                            .foregroundStyle(Theme.textSecondary)

                        Spacer()

                        if post.videoURL != nil || post.imageURL != nil {
                            Button {
                                savingMedia = true
                                Task {
                                    let result: MediaSaver.SaveResult
                                    if let videoURL = post.videoURL {
                                        result = await MediaSaver.saveVideo(from: videoURL)
                                    } else if let imageURL = post.imageURL {
                                        result = await MediaSaver.saveImage(from: imageURL)
                                    } else {
                                        result = .failed
                                    }
                                    savingMedia = false
                                    if result == .saved {
                                        mediaSaved = true
                                        try? await Task.sleep(for: .seconds(1.5))
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
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .font(.subheadline)

                    if session.isLoggedIn {
                        Button {
                            showCommentSheet = true
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

                    if !comments.isEmpty {
                        Divider().background(Theme.border)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Comments")
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                                .padding(.bottom, 12)

                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(comments) { comment in
                                    CommentRowView(comment: comment, session: session, client: client)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .defaultScrollAnchor(.top)
            .task {
                var result = (try? await client.fetchComments(permalink: post.permalink)) ?? []
                if result.count > 30 { result = Array(result.prefix(30)) }
                comments = result
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        comments = []
                        player?.pause()
                        player = nil
                        dismiss()
                    }
                    .foregroundStyle(Theme.primary)
                }
                if let action = removeAction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action.label) {
                            let postId = post.id
                            if session.isLoggedIn {
                                Task {
                                    let request = session.authenticatedRequest(
                                        url: action.apiURL,
                                        formData: ["id": "t3_\(postId)"]
                                    )
                                    try? await client.execute(request)
                                }
                            }
                            action.onComplete?(postId)
                            comments = []
                            player?.pause()
                            player = nil
                            dismiss()
                        }
                        .foregroundStyle(Theme.primary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showSubreddit) {
            SubredditCoverView(subreddit: post.subreddit, title: post.subredditNamePrefixed, client: client, filterStore: filterStore, session: session, subStore: subStore, blockStore: blockStore) {
                showSubreddit = false
            }
        }
        .sheet(isPresented: $showCommentSheet) {
            ComposeReplySheet(thingID: "t3_\(post.id)", session: session, client: client, isPresented: $showCommentSheet)
        }
        .fullScreenCover(isPresented: $showMediaViewer) {
            if let videoURL = post.videoURL {
                VideoViewerView(url: videoURL, aspectRatio: post.videoAspectRatio)
            } else if post.isGallery && !post.galleryItems.isEmpty {
                GalleryViewerView(items: post.galleryItems)
            } else if let imageURL = post.imageURL {
                GalleryViewerView(items: [GalleryMedia(id: 0, url: imageURL, isAnimated: false)])
            }
        }
        .sheet(isPresented: $showShareSheet) {
            PostShareSheet(url: post.redditURL, title: post.title, imageURL: post.imageURL)
        }
    }
}

struct CommentRowView: View {
    let comment: Comment
    let session: RedditSession
    let client: RedditClient
    @State private var collapsed = false
    @State private var selecting = false
    @State private var showReplySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if !collapsed {
                if selecting {
                    SelectableTextView(text: comment.body)
                } else {
                    CommentBodyView(content: comment.body)
                }

                HStack(spacing: 12) {
                    VoteControlsView(thingID: "t1_\(comment.id)", initialScore: comment.score, session: session, client: client, inactiveColor: Theme.textMuted)

                    if session.isLoggedIn {
                        Button {
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
                        CommentRowView(comment: reply, session: session, client: client)
                            .padding(.leading, 16)
                    }
                }

                if comment.moreCount > 0 {
                    Text("\(comment.moreCount) more replies")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 4)
                        .padding(.leading, 16)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, CGFloat(comment.depth * 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                withAnimation(.easeInOut(duration: 0.2)) { selecting = false }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
            }
        }
        .onLongPressGesture {
            guard !collapsed else { return }
            withAnimation(.easeInOut(duration: 0.2)) { selecting = true }
        }
        .overlay(alignment: .leading) {
            if comment.depth > 0 {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 2)
                    .padding(.leading, CGFloat((comment.depth - 1) * 12))
            }
        }
        .sheet(isPresented: $showReplySheet) {
            ComposeReplySheet(thingID: "t1_\(comment.id)", session: session, client: client, isPresented: $showReplySheet)
        }
    }
}

struct CommentBodyView: View {
    let content: String
    var textFont: Font = .subheadline
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
        let parts = Self.parse(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    }
                case .image(let url):
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
                case .gif(let url):
                    AnimatedGIFView(url: url)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .link(let title, let url):
                    Text(title)
                        .font(textFont)
                        .foregroundStyle(Theme.primary)
                        .underline()
                        .onTapGesture { openURL(url) }
                }
            }
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

    static func parse(_ text: String) -> [BodyPart] {
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
                    if isImageURL(urlStr) {
                        parts.append(.image(url))
                    } else {
                        parts.append(.link(linkText, url))
                    }
                }
            } else if isImageURL(full), let url = URL(string: full) {
                // Bare image URL
                parts.append(.image(url))
            } else if let url = URL(string: full) {
                // Bare non-image URL
                let display = full
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                parts.append(.link(display, url))
            }

            lastEnd = range.location + range.length
        }

        if lastEnd < nsText.length {
            parts.append(.text(nsText.substring(from: lastEnd)))
        }

        return parts
    }

    private static func isImageURL(_ urlStr: String) -> Bool {
        let lower = urlStr.lowercased()
        return imageExtensions.contains { lower.contains(".\($0)") }
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
        result = result.replacingOccurrences(of: ">!", with: "")
        result = result.replacingOccurrences(of: "!<", with: "")
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
    let session: RedditSession
    let client: RedditClient
    var inactiveColor: Color = Theme.textSecondary

    @State private var voted: Int = 0
    @State private var displayScore: Int

    init(thingID: String, initialScore: Int, session: RedditSession, client: RedditClient, inactiveColor: Color = Theme.textSecondary) {
        self.thingID = thingID
        self.session = session
        self.client = client
        self.inactiveColor = inactiveColor
        _displayScore = State(initialValue: initialScore)
    }

    var body: some View {
        HStack(spacing: session.isLoggedIn ? 8 : 6) {
            if session.isLoggedIn {
                Button {
                    let newDir = voted == 1 ? 0 : 1
                    let scoreDelta = newDir - voted
                    voted = newDir
                    displayScore += scoreDelta
                    Task {
                        let request = session.authenticatedRequest(
                            url: RedditAPI.vote,
                            formData: ["id": thingID, "dir": "\(newDir)"]
                        )
                        try? await client.execute(request)
                    }
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
                    let scoreDelta = newDir - voted
                    voted = newDir
                    displayScore += scoreDelta
                    Task {
                        let request = session.authenticatedRequest(
                            url: RedditAPI.vote,
                            formData: ["id": thingID, "dir": "\(newDir)"]
                        )
                        try? await client.execute(request)
                    }
                } label: {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(voted == -1 ? Theme.downvote : inactiveColor)
                }
            } else {
                Image(systemName: "arrow.down")
                    .foregroundStyle(inactiveColor)
            }
        }
    }
}

struct ComposeReplySheet: View {
    let thingID: String
    let session: RedditSession
    let client: RedditClient
    @Binding var isPresented: Bool
    @State private var text = ""
    @State private var posting = false

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
                        guard !isEmpty else { return }
                        posting = true
                        Task {
                            let request = session.authenticatedRequest(
                                url: RedditAPI.comment,
                                formData: [
                                    "thing_id": thingID,
                                    "text": text
                                ]
                            )
                            try? await client.execute(request)
                            posting = false
                            text = ""
                            isPresented = false
                        }
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
    }
}
