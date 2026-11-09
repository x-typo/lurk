import Foundation
import Testing
@testable import Lurk

@Suite("Subreddit feed API", .serialized)
@MainActor
struct SubredditFeedAPITests {
    // Signed in, Reddit answers `/r/<name>/hot.json` with 403; the bare listing is its default hot sort.
    @Test("Subreddit feeds read the default-sort listing and pass pagination")
    func listingRequests() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        SubredditFeedURLProtocol.stub(data: try JSONSerialization.data(withJSONObject: [
            "data": ["after": "t3_next", "children": []]
        ]))
        let client = RedditClient(session: session)

        let first = try await client.fetchSubredditPosts("interestingasfuck")
        _ = try await client.fetchSubredditPosts("interestingasfuck", after: "t3_next")

        #expect(first.data.after == "t3_next")
        let requests = SubredditFeedURLProtocol.requests
        #expect(requests.count == 2)
        for request in requests {
            let url = try #require(request.url)
            #expect(url.host == "www.reddit.com")
            #expect(url.path == "/r/interestingasfuck/.json")
            #expect(request.httpMethod == "GET")
            #expect(query(url, "limit") == "25")
            #expect(query(url, "raw_json") == "1")
        }
        #expect(query(try #require(requests.first?.url), "after") == nil)
        #expect(query(try #require(requests.last?.url), "after") == "t3_next")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubredditFeedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}

private nonisolated final class SubredditFeedURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseData = Data()
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func stub(data: Data) {
        lock.lock()
        defer { lock.unlock() }
        responseData = data
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let data = Self.responseData
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
