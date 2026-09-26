#if DEBUG
import SwiftUI

struct ReadingSimulatorFixtureView: View {
    private enum Sample: String, Identifiable {
        case comments, empty, crosspost, collapseScroll
        var id: String { rawValue }
    }

    @State private var session = RedditSession(restoringSession: false)
    @State private var filters = PostFilterStore()
    @State private var blocks = BlockedSubredditStore()
    @State private var mutes = MuteStore(defaults: freshMuteDefaults())
    @State private var hideSync = PostHideSync()
    @State private var engagement = EngagementStore()
    @State private var subscriptions = SubredditStore()
    @State private var playback = InlineGIFPlaybackStore()
    @State private var client = makeOfflineClient()
    @State private var selectedSample: Sample?
    @State private var attempts = 0
    @State private var requests = 0
    @State private var largeText = false
    @State private var pagination = false
    @State private var lastBrowserURL: URL?
    @State private var moreAttempts = 0

    private static let firstID = "abc123"
    private static let sampleSubreddit = "readingqa"
    private static let posts = [
        makePost(id: firstID, title: "First sample post"),
        makePost(id: "readingqa_second", title: "Second sample post")
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Reading fixture")
                .font(.headline)
            HStack {
                Button("Comments") {
                    attempts = 0
                    moreAttempts = 0
                    lastBrowserURL = nil
                    selectedSample = .comments
                }
                Button("Empty comments") {
                    selectedSample = .empty
                }
                Toggle("Large text", isOn: $largeText)
            }
            HStack {
                Button(filters.isHidden(Self.firstID) ? "Unhide first" : "Hide first") {
                    if filters.isHidden(Self.firstID) {
                        filters.unhidePost(Self.firstID)
                    } else {
                        filters.hidePost(Self.firstID)
                    }
                }
                Button(blocks.isBlocked(Self.sampleSubreddit) ? "Unblock sample" : "Block sample") {
                    if blocks.isBlocked(Self.sampleSubreddit) {
                        blocks.unblock(Self.sampleSubreddit)
                    } else {
                        blocks.block(Self.sampleSubreddit)
                    }
                }
            }
            HStack {
                Button("Crosspost") {
                    lastBrowserURL = nil
                    selectedSample = .crosspost
                }
                Button("Pagination sample") {
                    requests = 0
                    pagination.toggle()
                }
                if pagination {
                    Button("Hide tail") {
                        for post in Self.paginationPosts.dropFirst() {
                            filters.hidePost(post.id)
                        }
                    }
                }
            }
            Button("Collapse scroll") {
                lastBrowserURL = nil
                selectedSample = .collapseScroll
            }
            Text("Feed requests: \(requests)")
                .font(.caption)
            PaginatedFeedView(subredditNavigation: .none) { after in
                requests += 1
                if !pagination {
                    return try Self.listing(posts: Self.posts)
                }
                if after == nil {
                    return try Self.listing(posts: Self.paginationPosts, after: "readingqa_next")
                }
                return try Self.listing(posts: [Self.makePost(id: "readingqa_next", title: "Next-page sample post")])
            }
            .id(pagination)
        }
        .padding(.top, 12)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.primary)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(largeText ? .accessibility1 : .large)
        .task {
            for post in Self.paginationPosts + Self.posts {
                filters.unhidePost(post.id)
            }
            blocks.unblock(Self.sampleSubreddit)
        }
        .sheet(item: $selectedSample) { sample in
            PostDetailView(post: sample == .crosspost ? Self.crosspost : Self.posts[0], commentsFetch: {
                if sample == .collapseScroll { return Self.collapseScrollComments }
                if sample != .comments { return [] }
                attempts += 1
                try await Task.sleep(for: .milliseconds(300))
                if attempts == 1 {
                    throw URLError(.notConnectedToInternet)
                }
                return Self.comments
            }, commentsFetchMore: { more in
                moreAttempts += 1
                try await Task.sleep(for: .milliseconds(300))
                if moreAttempts == 1 {
                    throw URLError(.notConnectedToInternet)
                }
                return Self.loadedReplies(for: more)
            })
            .dynamicTypeSize(largeText ? .accessibility1 : .large)
            .safeAreaInset(edge: .bottom) {
                if let lastBrowserURL {
                    Text("Browser destination: \(lastBrowserURL.absoluteString)")
                        .font(.caption)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surface)
                }
            }
        }
        .environment(session)
        .environment(filters)
        .environment(blocks)
        .environment(mutes)
        .environment(hideSync)
        .environment(engagement)
        .environment(subscriptions)
        .environment(playback)
        .environment(\.redditClient, client)
        .environment(\.openURL, OpenURLAction { url in
            lastBrowserURL = url
            return .handled
        })
    }

    private static func makePost(id: String, title: String) -> Post {
        Post(
            id: id, title: title, author: "sample_reader",
            subreddit: sampleSubreddit, subredditNamePrefixed: "r/\(sampleSubreddit)",
            score: 12, numComments: 4, createdUtc: Date().timeIntervalSince1970,
            permalink: "/r/readingqa/comments/\(id)/sample/",
            url: "https://www.reddit.com/r/readingqa/", selftext: "",
            isSelf: true, isVideo: false, stickied: false, over18: false,
            postHint: nil, media: nil, secureMedia: nil, preview: nil,
            galleryData: nil, mediaMetadata: nil
        )
    }

    // Each fixture launch starts with only the seeded bots muted.
    private static func freshMuteDefaults() -> UserDefaults {
        let suite = "com.xtypo.Lurk.readingQA.mutes"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private static func makeOfflineClient() -> RedditClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadingFixtureURLProtocol.self]
        return RedditClient(session: URLSession(configuration: configuration))
    }

    private static var paginationPosts: [Post] {
        [posts[0]] + (2...8).map { makePost(id: "readingqa_page_\($0)", title: "Pagination sample post \($0)") }
    }

    private static func listing(posts: [Post], after: String? = nil) throws -> RedditListing {
        let children = posts.map { post in
            ["data": [
                "id": post.id, "title": post.title, "author": post.author,
                "subreddit": post.subreddit, "subreddit_name_prefixed": post.subredditNamePrefixed,
                "score": post.score, "num_comments": post.numComments, "created_utc": post.createdUtc,
                "permalink": post.permalink, "url": post.url, "selftext": post.selftext,
                "is_self": true, "is_video": false, "stickied": false, "over_18": false
            ] as [String: Any]]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "data": ["children": children, "after": after as Any? ?? NSNull()]
        ])
        return try RedditAPI.decoder.decode(RedditListing.self, from: data)
    }

    private static func comment(
        _ id: String,
        _ author: String,
        _ body: String,
        score: Int = 5,
        isSubmitter: Bool = false,
        likes: Bool? = nil,
        replies: [CommentNode] = []
    ) -> CommentNode {
        .comment(Comment(
            id: id, author: author, body: body, score: score,
            createdUtc: Date().timeIntervalSince1970,
            isSubmitter: isSubmitter, likes: likes
        ), replies: replies)
    }

    // Six levels deep, ending in a continuation, plus reply-level and top-level "more" placeholders.
    private static var comments: [CommentNode] {
        var thread: [CommentNode] = [.more(CommentMore(parentID: "t1_deep5", count: 0, childIDs: []))]
        for level in (0...5).reversed() {
            thread = [comment(
                "deep\(level)", "reader_\(level)",
                level == 0
                    ? "The ending is >!a friendly dragon!<. The secret link is >![the map](https://example.com/secret)!<."
                    : "Reply level \(level). This sentence should have enough room to read comfortably.",
                isSubmitter: level == 0, likes: level == 1 ? true : nil, replies: thread
            )]
        }
        return thread + [
            comment("second", "second_reader", "A second top-level comment with a short nested thread.",
                    score: 42, likes: false, replies: [
                        comment("secondreply", "nested_reader", "One loaded reply."),
                        .more(CommentMore(parentID: "t1_second", count: 3, childIDs: ["morea", "moreb", "morec"])),
                    ]),
            comment("third", "third_reader", "A third top-level comment.", score: 7),
            .more(CommentMore(parentID: "t3_\(firstID)", count: 12, childIDs: ["topa", "topb", "topc"])),
        ]
    }

    private static func loadedReplies(for more: CommentMore) -> [LoadedCommentNode] {
        if more.continuesThread {
            return CommentNode.flatten([
                comment("deep6", "deeper_reader", "Loaded in the app instead of Safari.", replies: [
                    comment("deep7", "deepest_reader", "Level 7 still has room to read."),
                ]),
            ], under: more.parentID)
        }
        return CommentNode.flatten(more.childIDs.enumerated().map { index, id in
            comment(id, "loaded_\(index + 1)", "Loaded reply \(index + 1).")
        }, under: more.parentID)
    }

    private static let collapseScrollComments: [CommentNode] = (1...30).map { index in
        let replies: [CommentNode] = index == 1 ? [
            comment(
                "collapsechild", "scroll_child",
                "Collapse this nested reply, then collapse and expand its parent. This reply should stay collapsed.",
                score: 3,
                replies: [comment(
                    "collapsegrandchild", "scroll_grandchild",
                    "This grandchild is hidden whenever its parent is collapsed.", score: 1
                )]
            )
        ] : []
        return comment(
            "collapse\(index)", "scroll_\(index)",
            "Comment \(index). Collapse the first five comments, scroll far down to later numbered comments, then return. Each collapsed comment should remain closed for this visit. Closing and reopening the post starts a fresh visit.",
            score: index, replies: replies
        )
    }

    private static let crosspost: Post = {
        let data = Data("""
        {
          "id":"abc123", "title":"A post shared to another community", "author":"crossposter",
          "subreddit":"readingqa", "subreddit_name_prefixed":"r/readingqa", "score":12,
          "num_comments":4, "created_utc":0, "permalink":"/r/readingqa/comments/abc123/shared/",
          "url":"https://www.reddit.com/r/original/comments/def456/original/", "selftext":"My note on this crosspost.",
          "is_self":false, "is_video":false, "stickied":false, "over_18":false,
          "crosspost_parent":"t3_def456", "crosspost_parent_list":[{
            "id":"def456", "title":"The original discussion", "author":"original_author",
            "subreddit":"original", "subreddit_name_prefixed":"r/original",
            "permalink":"/r/original/comments/def456/original/",
            "url":"https://example.com/article", "selftext":"This text belongs to the original post and should remain visible here.",
            "is_self":false, "is_video":false
          }]
        }
        """.utf8)
        return try! RedditAPI.decoder.decode(Post.self, from: data)
    }()
}

private nonisolated final class ReadingFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
