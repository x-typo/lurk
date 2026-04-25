import Foundation

enum RedditAPI {
    nonisolated static let userAgent = "ios:com.lurk.app:v1.0"
    static let hide = URL(string: "https://www.reddit.com/api/hide")!
    static let unhide = URL(string: "https://www.reddit.com/api/unhide")!
    static let unsave = URL(string: "https://www.reddit.com/api/unsave")!
    static let vote = URL(string: "https://www.reddit.com/api/vote")!
    static let comment = URL(string: "https://www.reddit.com/api/comment")!
    static let subscribe = URL(string: "https://www.reddit.com/api/subscribe")!
}

actor RedditClient {
    private let baseURL = "https://www.reddit.com"
    private static let pageSize = "25"
    private static let profilePageSize = "20"
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": RedditAPI.userAgent
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchHomePosts(after: String? = nil) async throws -> RedditListing {
        var components = try buildComponents(path: "/top/.json")
        components.queryItems = [
            URLQueryItem(name: "sort", value: "top"),
            URLQueryItem(name: "t", value: "day"),
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

    func fetchComments(permalink: String) async throws -> [Comment] {
        let path = "\(permalink).json"
        var components = try buildComponents(path: path)
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let listings = try decoder.decode([CommentListing].self, from: data)

        guard listings.count >= 2 else { return [] }
        return Comment.parse(from: listings[1])
    }

    func execute(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
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
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(SavedCommentListing.self, from: data)
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
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
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
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(RedditListing.self, from: data)
    }
}
