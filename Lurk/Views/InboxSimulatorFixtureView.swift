#if DEBUG
import SwiftUI

struct InboxSimulatorFixtureView: View {
    @State private var readIDs: Set<String> = []
    @State private var resetID = 0
    @State private var largeText = false
    @State private var failNextRead = false
    @State private var session = RedditSession()
    @State private var filters = PostFilterStore()
    @State private var blocks = BlockedSubredditStore()
    @State private var subscriptions = SubredditStore()
    @State private var playback = InlineGIFPlaybackStore()
    @State private var client = makeOfflineClient()

    var body: some View {
        InboxContentView(account: "sample_reader", fetchPage: { filter, _ in
            try await Task.sleep(for: .milliseconds(250))
            return try listing(filter: filter)
        }, markRead: { reply in
            try await Task.sleep(for: .milliseconds(300))
            if failNextRead {
                failNextRead = false
                throw URLError(.notConnectedToInternet)
            }
            readIDs.insert(reply.id)
        })
        .id(resetID)
        .dynamicTypeSize(largeText ? .accessibility1 : .large)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("SAMPLE DATA")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Menu("Preview options") {
                    Button("Reset sample replies") {
                        readIDs = []
                        resetID += 1
                    }
                    Toggle("Large text", isOn: $largeText)
                    Toggle("Fail next mark read", isOn: $failNextRead)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.background)
        }
        .environment(session)
        .environment(filters)
        .environment(blocks)
        .environment(subscriptions)
        .environment(playback)
        .environment(\.redditClient, client)
        .environment(\.openURL, OpenURLAction { _ in .handled })
        .tint(Theme.primary)
        .preferredColorScheme(.dark)
    }

    private func listing(filter: InboxFilter) throws -> InboxListing {
        let samples: [(String, String, String, String, String, Bool, Double)] = [
            ("sample1", "ios", "pixel_reader", "What’s one small iPhone feature you use every day?",
             "The back-tap shortcut! I set mine to take a screenshot. Took a few days to get used to it, but now I use it all the time.", true, 480),
            ("sample2", "books", "paper_trails", "A book you wish you could read again for the first time",
             "I had the same reaction to the ending. The little details hit so differently on a second read.", true, 2520),
            ("sample3", "SwiftUI", "view_builder", "Keeping a reading app simple",
             "Agreed. A few thoughtful touches make a bigger difference than adding another screen.", false, 86400)
        ]
        let children = samples.compactMap { id, subreddit, author, title, body, wasUnread, age -> [String: Any]? in
            let unread = wasUnread && !readIDs.contains("t1_\(id)")
            guard filter == .all || unread else { return nil }
            return ["kind": "t1", "data": [
                "id": id, "name": "t1_\(id)", "author": author,
                "body": body, "created_utc": Date().timeIntervalSince1970 - age,
                "subreddit": subreddit, "link_title": title, "new": unread,
                "context": "/r/\(subreddit)/comments/preview/sample/\(id)/",
                "link_permalink": "/r/\(subreddit)/comments/preview/sample/"
            ]]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "data": ["children": children, "after": NSNull()]
        ])
        return try RedditAPI.decoder.decode(InboxListing.self, from: data)
    }

    private static func makeOfflineClient() -> RedditClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.protocolClasses = [InboxFixtureURLProtocol.self]
        return RedditClient(session: URLSession(configuration: configuration))
    }
}

private final class InboxFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
