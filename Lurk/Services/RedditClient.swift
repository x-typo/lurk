import Foundation

enum RedditAPI {
    nonisolated static let userAgent = "ios:com.lurk.app:v1.0"
    static let hide = URL(string: "https://www.reddit.com/api/hide")!
    static let unhide = URL(string: "https://www.reddit.com/api/unhide")!
    static let save = URL(string: "https://www.reddit.com/api/save")!
    static let unsave = URL(string: "https://www.reddit.com/api/unsave")!
    static let vote = URL(string: "https://www.reddit.com/api/vote")!
    static let comment = URL(string: "https://www.reddit.com/api/comment")!
    static let editUserText = URL(string: "https://www.reddit.com/api/editusertext")!
    static let deleteComment = URL(string: "https://www.reddit.com/api/del")!
    static let subscribe = URL(string: "https://www.reddit.com/api/subscribe")!
    static let readMessage = URL(string: "https://www.reddit.com/api/read_message")!

    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    nonisolated static func responseSummary(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String {
                return message
            }
            if let error = json["error"], !(error is NSNull) {
                return String(describing: error)
            }
            if let envelope = json["json"] as? [String: Any],
               let errors = envelope["errors"] as? [Any],
               !errors.isEmpty {
                let messages = errors.compactMap { item -> String? in
                    guard let fields = item as? [Any] else { return nil }
                    let parts = fields.compactMap { $0 as? String }.filter { !$0.isEmpty }
                    return parts.isEmpty ? nil : parts.joined(separator: ": ")
                }
                if !messages.isEmpty { return messages.joined(separator: "\n") }
            }
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if text.contains("You've been blocked by network security") {
            return "You've been blocked by Reddit network security."
        }
        let collapsed = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(180))
    }
}

enum RedditClientError: LocalizedError {
    case apiErrors([String])
    case httpStatus(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiErrors(let errors):
            return errors.joined(separator: "\n")
        case .httpStatus(let status, let summary):
            if let summary, !summary.isEmpty {
                return "Reddit returned \(status): \(summary)"
            }
            return "Reddit returned HTTP \(status)."
        case .invalidResponse:
            return "Reddit returned an invalid response."
        }
    }
}

actor RedditClient {
    private let baseURL = "https://www.reddit.com"
    private static let pageSize = "25"
    private static let profilePageSize = "20"
    private static let moreChildrenBatchSize = 100
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": RedditAPI.userAgent
        ]
        self.session = URLSession(configuration: config)
    }

    init(session: URLSession) {
        self.session = session
    }

    func fetchHomePosts(
        sort: SortType = .top,
        time: TimeFilter = .day,
        after: String? = nil
    ) async throws -> RedditListing {
        var components = try buildComponents(path: "/\(sort.rawValue).json")
        components.queryItems = [
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "t", value: time.rawValue),
        ] + baseQueryItems(after: after)
        guard let url = components.url else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    func fetchPopularPosts(
        sort: SortType = .top,
        time: TimeFilter = .day,
        after: String? = nil
    ) async throws -> RedditListing {
        var components = try buildComponents(path: "/r/popular/\(sort.rawValue).json")
        components.queryItems = [
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "t", value: time.rawValue),
        ] + baseQueryItems(after: after)
        guard let url = components.url else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    func fetchSubredditPosts(
        _ subreddit: String,
        sort: SortType = .hot,
        after: String? = nil
    ) async throws -> RedditListing {
        let encoded = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subreddit
        var components = try buildComponents(path: "/r/\(encoded)/\(sort.rawValue).json")
        components.queryItems = baseQueryItems(after: after)
        guard let url = components.url else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    func fetchComments(permalink: String) async throws -> [CommentNode] {
        let path = "\(permalink).json"
        var components = try buildComponents(path: path)
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)

        let listings = try RedditAPI.decoder.decode([CommentListing].self, from: data)

        guard listings.count >= 2 else { return [] }
        return CommentNode.parse(from: listings[1])
    }

    func fetchPost(id: String) async throws -> Post {
        guard Comment.isRedditID(id) else { throw URLError(.badURL) }
        var components = try buildComponents(path: "/by_id/t3_\(id).json")
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)

        let listing = try RedditAPI.decoder.decode(RedditListing.self, from: data)
        guard let post = listing.data.children.first?.data else { throw URLError(.fileDoesNotExist) }
        return post
    }

    // One comment with three levels of parents, the way Reddit's context links show it.
    func fetchCommentContext(postID: String, commentID: String) async throws -> [CommentNode] {
        guard Comment.isRedditID(postID), Comment.isRedditID(commentID) else { throw URLError(.badURL) }
        var components = try buildComponents(path: "/comments/\(postID).json")
        components.queryItems = [
            URLQueryItem(name: "comment", value: commentID),
            URLQueryItem(name: "context", value: "3"),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)

        let listings = try RedditAPI.decoder.decode([CommentListing].self, from: data)
        guard listings.count >= 2 else { return [] }
        return CommentNode.parse(from: listings[1])
    }

    // Returns loaded nodes, each paired with its parent, for `CommentNode.merging`.
    func fetchMoreComments(postID: String, more: CommentMore) async throws -> [LoadedCommentNode] {
        guard Comment.isRedditID(postID) else { throw URLError(.badURL) }
        if more.continuesThread {
            return try await fetchContinuedThread(postID: postID, more: more)
        }

        let batch = Array(more.childIDs.prefix(Self.moreChildrenBatchSize))
        var components = try buildComponents(path: "/api/morechildren.json")
        components.queryItems = [
            URLQueryItem(name: "api_type", value: "json"),
            URLQueryItem(name: "link_id", value: "t3_\(postID)"),
            URLQueryItem(name: "children", value: batch.joined(separator: ",")),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        try validateRedditErrors(in: data)

        let things = try RedditAPI.decoder.decode(MoreChildrenResponse.self, from: data).json.data?.things ?? []
        var loaded = CommentNode.loaded(fromFlat: things)
        let remaining = Array(more.childIDs.dropFirst(batch.count))
        if !remaining.isEmpty {
            loaded.append(LoadedCommentNode(parentID: more.parentID, node: .more(CommentMore(
                parentID: more.parentID,
                count: max(more.count - batch.count, remaining.count),
                childIDs: remaining
            ))))
        }
        return loaded
    }

    private func fetchContinuedThread(postID: String, more: CommentMore) async throws -> [LoadedCommentNode] {
        let commentID = String(more.parentID.dropFirst(3))
        guard more.parentID.hasPrefix("t1_"), Comment.isRedditID(commentID) else { throw URLError(.badURL) }

        var components = try buildComponents(path: "/comments/\(postID).json")
        components.queryItems = [
            URLQueryItem(name: "comment", value: commentID),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)

        let listings = try RedditAPI.decoder.decode([CommentListing].self, from: data)
        guard listings.count >= 2,
              let parent = listings[1].data.children.first(where: { $0.kind == "t1" && $0.data.id == commentID }),
              case .listing(let replies) = parent.data.replies
        else { return [] }
        return CommentNode.flatten(
            CommentNode.parse(replies.data.children, parentID: more.parentID),
            under: more.parentID
        )
    }

    func execute(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        try validateRedditErrors(in: data)
    }

    func fetchSavedPosts(username: String, after: String? = nil) async throws -> RedditListing {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = try buildComponents(path: "/user/\(encoded)/saved/.json")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "links"),
            URLQueryItem(name: "limit", value: Self.profilePageSize),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    func fetchSavedComments(username: String, after: String? = nil) async throws -> SavedCommentListing {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = try buildComponents(path: "/user/\(encoded)/saved/.json")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "comments"),
            URLQueryItem(name: "limit", value: Self.profilePageSize),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try RedditAPI.decoder.decode(SavedCommentListing.self, from: data)
    }

    func fetchUserComments(username: String, after: String? = nil) async throws -> UserCommentListing {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = try buildComponents(path: "/user/\(encoded)/comments/.json")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: Self.profilePageSize),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try RedditAPI.decoder.decode(UserCommentListing.self, from: data)
    }

    func fetchInboxReplies(filter: InboxFilter = .all, after: String? = nil) async throws -> InboxListing {
        let path = filter == .unread ? "/message/unread/.json" : "/message/comments/.json"
        var components = try buildComponents(path: path)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: Self.profilePageSize),
            URLQueryItem(name: "raw_json", value: "1"),
            URLQueryItem(name: "mark", value: "false"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try RedditAPI.decoder.decode(InboxListing.self, from: data).filtered(for: filter)
    }

    func fetchHiddenPosts(username: String, after: String? = nil) async throws -> RedditListing {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = try buildComponents(path: "/user/\(encoded)/hidden/.json")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: Self.profilePageSize),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    func fetchSubscribedSubreddits() async throws -> [String] {
        var names: [String] = []
        var after: String?
        var pageCount = 0
        repeat {
            var components = try buildComponents(path: "/subreddits/mine/subscriber.json")
            var items: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "raw_json", value: "1"),
            ]
            if let after { items.append(URLQueryItem(name: "after", value: after)) }
            components.queryItems = items
            guard let url = components.url else { throw URLError(.badURL) }
            let (data, response) = try await session.data(from: url)
            try validateHTTPResponse(response, data: data)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let dataDict = json?["data"] as? [String: Any]
            let children = dataDict?["children"] as? [[String: Any]] ?? []
            names += children.compactMap { child in
                guard let d = child["data"] as? [String: Any] else { return nil }
                return d["display_name"] as? String
            }
            let nextAfter = dataDict?["after"] as? String
            after = (nextAfter?.isEmpty == false) ? nextAfter : nil
            pageCount += 1
        } while after != nil && pageCount < 50
        return names
    }

    private func buildComponents(path: String) throws -> URLComponents {
        guard let components = URLComponents(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        return components
    }

    private func baseQueryItems(after: String? = nil) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: Self.pageSize),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        return items
    }

    private func fetch(_ url: URL) async throws -> RedditListing {
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        return try RedditAPI.decoder.decode(RedditListing.self, from: data)
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RedditClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw RedditClientError.httpStatus(http.statusCode, RedditAPI.responseSummary(from: data))
        }
    }

    private func validateRedditErrors(in data: Data) throws {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = json["json"] as? [String: Any],
              let errors = envelope["errors"] as? [Any],
              !errors.isEmpty
        else { return }

        let messages = errors.compactMap { error -> String? in
            guard let fields = error as? [Any], !fields.isEmpty else { return nil }
            let parts = fields.compactMap { $0 as? String }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ": ")
        }
        throw RedditClientError.apiErrors(messages.isEmpty ? ["Reddit rejected the request."] : messages)
    }
}
