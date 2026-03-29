import Foundation

actor RedditClient {
    private let baseURL = "https://www.reddit.com"
    private static let pageSize = "25"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "ios:com.lurk.app:v1.0"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchPopularPosts(
        sort: SortType = .top,
        time: TimeFilter = .day,
        after: String? = nil
    ) async throws -> RedditListing {
        var components = try buildComponents(path: "/r/popular/\(sort.rawValue).json")
        var items = baseQueryItems(after: after)
        items.insert(URLQueryItem(name: "t", value: time.rawValue), at: 0)
        components.queryItems = items
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RedditListing.self, from: data)
    }
}
