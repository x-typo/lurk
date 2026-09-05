import Foundation
import Testing
@testable import Lurk

@Suite("Inbox API", .serialized)
@MainActor
struct InboxAPITests {
    @Test("Both filters preserve read state and pass pagination to their listing endpoint")
    func listingRequests() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        InboxAPIURLProtocol.stub(data: try listingData(children: []))
        let client = RedditClient(session: session)

        _ = try await client.fetchInboxReplies(filter: .unread, after: "t1_next+cursor")
        _ = try await client.fetchInboxReplies()

        let requests = InboxAPIURLProtocol.requests
        #expect(requests.count == 2)
        let unread = try #require(requests.first?.url)
        let all = try #require(requests.last?.url)
        #expect(unread.path == "/message/unread/.json")
        #expect(all.path == "/message/comments/.json")
        for request in requests {
            let url = try #require(request.url)
            #expect(url.host == "www.reddit.com")
            #expect(request.httpMethod == "GET")
            #expect(query(url, "mark") == "false")
            #expect(query(url, "limit") == "20")
            #expect(query(url, "raw_json") == "1")
        }
        #expect(query(unread, "after") == "t1_next+cursor")
        #expect(query(all, "after") == nil)
    }

    @Test("Unread excludes read comments and private messages; All keeps both comment states")
    func filterReplyStates() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        InboxAPIURLProtocol.stub(data: try listingData(children: [
            comment("unread", unread: true),
            comment("read", unread: false),
            comment("unspecified"),
            ["kind": "t4", "data": [
                "id": "private", "name": "t4_private", "author": "reader",
                "body": "A private message", "created_utc": 1_700_000_000,
                "subreddit": "swift", "link_title": "A message",
                "subject": "comment reply", "was_comment": false, "new": true
            ]]
        ]))
        let client = RedditClient(session: session)

        let unread = try await client.fetchInboxReplies(filter: .unread)
        #expect(unread.data.replies.map(\.id) == ["t1_unread", "t1_unspecified"])
        #expect(unread.data.replies.allSatisfy { $0.isUnread })
        #expect(unread.data.after == "t1_next")

        let all = try await client.fetchInboxReplies(filter: .all)
        #expect(all.data.replies.map(\.id) == ["t1_unread", "t1_read", "t1_unspecified"])
        #expect(all.data.replies.map(\.isUnread) == [true, false, false])
        #expect(all.data.after == "t1_next")
    }

    @Test("Malformed children are skipped while comment variants and optional metadata survive")
    func tolerantCommentDecoding() throws {
        var minimal = comment("minimal", unread: true)
        var minimalData = try #require(minimal["data"] as? [String: Any])
        minimalData["author"] = NSNull()
        minimalData.removeValue(forKey: "link_title")
        minimalData["unknown_field"] = ["future": [1, 2]]
        minimal["data"] = minimalData

        var legacy = comment("legacy", unread: true)
        legacy.removeValue(forKey: "kind")
        var legacyData = try #require(legacy["data"] as? [String: Any])
        legacyData["was_comment"] = true
        legacy["data"] = legacyData

        let listing = try RedditAPI.decoder.decode(InboxListing.self, from: listingData(children: [
            NSNull(), 42, ["kind": "t1", "data": ["id": "broken"]],
            ["kind": "t1", "data": ["new": "not a boolean"]], minimal, legacy
        ]))

        #expect(listing.data.replies.map(\.id) == ["t1_minimal", "t1_legacy"])
        let reply = try #require(listing.data.replies.first)
        #expect(reply.author == "[deleted]")
        #expect(reply.linkTitle == "Comment reply")
        #expect(reply.subredditNamePrefixed == "r/swift")
        #expect(reply.thingID == "t1_minimal")
        #expect(reply.contextURL?.absoluteString == "https://www.reddit.com/r/swift/comments/post/title/minimal/?context=3")
        #expect(reply.fullCommentsURL?.absoluteString == "https://www.reddit.com/r/swift/comments/post/title/")
        #expect(reply.isUnread)
    }

    @Test("Failed inbox responses are surfaced instead of looking like an empty inbox")
    func listingFailure() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        InboxAPIURLProtocol.stub(data: Data(#"{"message":"Forbidden"}"#.utf8), status: 403)
        let client = RedditClient(session: session)

        do {
            _ = try await client.fetchInboxReplies(filter: .unread)
            Issue.record("Expected an HTTP failure")
        } catch let RedditClientError.httpStatus(status, summary) {
            #expect(status == 403)
            #expect(summary == "Forbidden")
        }
    }

    @Test("Unread comment replies exclude mentions and post replies, matching All")
    func commentReplyCategories() throws {
        func item(_ id: String, subject: String?, parent: String?) -> [String: Any] {
            var value = comment(id, unread: true)
            var data = value["data"] as! [String: Any]
            data["subject"] = subject
            data["parent_id"] = parent
            value["data"] = data
            return value
        }
        let listing = try RedditAPI.decoder.decode(InboxListing.self, from: listingData(children: [
            item("reply", subject: "comment reply", parent: "t1_parent"),
            item("mention", subject: "username mention", parent: "t1_parent"),
            item("postreply", subject: "post reply", parent: "t3_post"),
            item("withoutsubject", subject: nil, parent: "t3_post"),
            item("legacy", subject: nil, parent: "t1_parent")
        ])).filtered(for: .unread)
        #expect(listing.data.replies.map(\.id) == ["t1_reply", "t1_legacy"])
    }

    @Test("Reply IDs cannot turn a single Mark read into a multi-item or message write")
    func validatesActionTarget() throws {
        var children: [[String: Any]] = [comment("valid", unread: true)]
        for name in ["t1_", "t1_good,t1_other", "t4_message", "t1_bad/name", "t1_bad%2Cother"] {
            var item = comment("ignored", unread: true)
            var data = item["data"] as! [String: Any]
            data["name"] = name
            item["data"] = data
            children.append(item)
        }
        let listing = try RedditAPI.decoder.decode(InboxListing.self, from: listingData(children: children))
        #expect(listing.data.replies.map(\.thingID) == ["t1_valid"])
    }

    @Test("Read actions accept Reddit success and propagate API or transport failures")
    func readActionResponses() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = RedditClient(session: session)
        var request = URLRequest(url: RedditAPI.readMessage)
        request.httpMethod = "POST"
        request.httpBody = Data("id=t1_selected".utf8)
        InboxAPIURLProtocol.stub(data: Data("{}".utf8))
        try await client.execute(request)
        let sent = try #require(InboxAPIURLProtocol.requests.first)
        #expect(sent.url?.path == "/api/read_message" && sent.httpMethod == "POST")

        InboxAPIURLProtocol.stub(data: Data(#"{"json":{"errors":[["BAD_ID","Invalid reply","id"]]}}"#.utf8))
        do {
            try await client.execute(request)
            Issue.record("Reddit JSON errors must keep the reply unread")
        } catch let RedditClientError.apiErrors(errors) {
            #expect(!errors.isEmpty)
        }
        InboxAPIURLProtocol.stub(data: Data("{}".utf8), status: 503)
        do {
            try await client.execute(request)
            Issue.record("HTTP failures must keep the reply unread")
        } catch let RedditClientError.httpStatus(status, _) {
            #expect(status == 503)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InboxAPIURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private func listingData(children: [Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "data": ["after": "t1_next", "children": children]
        ])
    }

    private func comment(_ id: String, unread: Bool? = nil) -> [String: Any] {
        var data: [String: Any] = [
            "id": id, "name": "t1_\(id)", "author": "reader", "body": "A reply",
            "created_utc": 1_700_000_000, "subreddit": "swift", "link_title": "A post",
            "context": "/r/swift/comments/post/title/\(id)/?context=3"
        ]
        if let unread { data["new"] = unread }
        return ["kind": "t1", "data": data]
    }
}

private nonisolated final class InboxAPIURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseData = Data()
    nonisolated(unsafe) private static var responseStatus = 200
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func stub(data: Data, status: Int = 200) {
        lock.lock()
        defer { lock.unlock() }
        responseData = data
        responseStatus = status
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let data = Self.responseData
        let status = Self.responseStatus
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
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
