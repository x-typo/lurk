import AVKit
import SwiftUI

struct PostDetailView: View {
    let post: Post
    let session: RedditSession
    let client: RedditClient
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var voted: Int = 0
    @State private var displayScore: Int
    @State private var comments: [Comment] = []
    @State private var showCommentSheet = false
    @State private var commentText = ""
    @State private var postingComment = false
    @State private var mediaSaved = false
    @State private var savingMedia = false

    init(post: Post, session: RedditSession, client: RedditClient) {
        self.post = post
        self.session = session
        self.client = client
        _displayScore = State(initialValue: post.score)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(post.subredditNamePrefixed)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
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

                    if let videoURL = post.videoURL {
                        VideoPlayer(player: player)
                            .aspectRatio(post.videoAspectRatio ?? 16/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onAppear {
                                player = AVPlayer(url: videoURL)
                                player?.play()
                            }
                            .onDisappear {
                                player?.pause()
                                player = nil
                            }
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
                    }

                    if !post.selftext.isEmpty {
                        CommentBodyView(content: post.selftext, textFont: .body)
                    }

                    HStack(spacing: 16) {
                        if session.isLoggedIn {
                            Button {
                                let newDir = voted == 1 ? 0 : 1
                                let scoreDelta = newDir - voted
                                voted = newDir
                                displayScore += scoreDelta
                                Task {
                                    let request = session.authenticatedRequest(
                                        url: RedditAPI.vote,
                                        formData: ["id": "t3_\(post.id)", "dir": "\(newDir)"]
                                    )
                                    try? await client.execute(request)
                                }
                            } label: {
                                Label(Formatters.score(displayScore), systemImage: voted == 1 ? "arrow.up.circle.fill" : "arrow.up")
                                    .foregroundStyle(voted == 1 ? Theme.primary : Theme.textSecondary)
                            }
                        } else {
                            Label(Formatters.score(displayScore), systemImage: "arrow.up")
                                .foregroundStyle(Theme.textSecondary)
                        }
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
                        }

                        ShareLink(item: post.redditURL) {
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
                                    CommentRowView(comment: comment)
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
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCommentSheet) {
            NavigationStack {
                VStack(spacing: 0) {
                    TextEditor(text: $commentText)
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
                            showCommentSheet = false
                        }
                        .foregroundStyle(Theme.primary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            postingComment = true
                            Task {
                                let request = session.authenticatedRequest(
                                    url: RedditAPI.comment,
                                    formData: [
                                        "thing_id": "t3_\(post.id)",
                                        "text": commentText
                                    ]
                                )
                                try? await client.execute(request)
                                postingComment = false
                                commentText = ""
                                showCommentSheet = false
                            }
                        } label: {
                            if postingComment {
                                ProgressView().tint(Theme.primary)
                            } else {
                                Text("Post")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(Theme.primary)
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postingComment)
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }
}

struct CommentRowView: View {
    let comment: Comment
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("u/\(comment.author)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Text(Formatters.timeAgo(comment.createdUtc))
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                if collapsed {
                    Text("+")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textMuted)
                }
                Text(Formatters.score(comment.score))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !collapsed {
                CommentBodyView(content: comment.body)

                if !comment.replies.isEmpty {
                    ForEach(comment.replies) { reply in
                        CommentRowView(comment: reply)
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
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
        }
        .overlay(alignment: .leading) {
            if comment.depth > 0 {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 2)
                    .padding(.leading, CGFloat((comment.depth - 1) * 12))
            }
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
                        Text(text)
                            .font(textFont)
                            .foregroundStyle(Theme.text)
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

    enum BodyPart {
        case text(String)
        case image(URL)
        case gif(URL)
        case link(String, URL)
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
}
