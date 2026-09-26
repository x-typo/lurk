import Foundation
import Testing
@testable import Lurk

// These tests never call logout() or syncCookies(from:): both touch the test host's real cookie
// and WebKit stores.
@MainActor
@Suite("Reddit session")
struct RedditSessionTests {
    private static let me = #"{"kind":"t2","data":{"name":"reader","modhash":"hash"}}"#

    @Test("A check that can't reach Reddit keeps the stored sign-in, and the retry signs in")
    func undeterminedCheckKeepsSession() async throws {
        let stub = LoginCheckStub([.failure(.timedOut), .response(200, Self.me)])
        let session = RedditSession(storedCookies: [try cookie()], sendLoginCheck: stub.send)
        await session.restoreTask?.value
        #expect(!session.isLoggedIn)
        #expect(session.needsLoginCheck)

        await session.checkLoginStatus()
        #expect(session.isLoggedIn)
        #expect(session.username == "reader")
        #expect(!session.needsLoginCheck)
        #expect(stub.requests.count == 2)
        #expect(stub.requests.last?.value(forHTTPHeaderField: "Cookie") == "reddit_session=abc")
    }

    @Test(
        "Reddit refusing the cookies, or answering without a user, signs out and drops them",
        arguments: [(403, #"{"message":"Forbidden"}"#), (401, ""), (200, "{}")]
    )
    func refusedCheckSignsOut(status: Int, body: String) async throws {
        let stub = LoginCheckStub([.response(status, body), .response(403, "")])
        let session = RedditSession(storedCookies: [try cookie()], sendLoginCheck: stub.send)
        await session.restoreTask?.value
        #expect(!session.isLoggedIn)
        #expect(!session.needsLoginCheck)

        await session.checkLoginStatus()
        #expect(stub.requests.last?.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Only a refusal or an answer without a user is a sign-out; anything else is undetermined")
    func classifiesResponses() throws {
        let url = try #require(URL(string: "https://www.reddit.com/api/me.json"))
        func result(_ status: Int, _ body: String) throws -> RedditSession.LoginCheckResult {
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return RedditSession.loginCheckResult(data: Data(body.utf8), response: response)
        }
        #expect(try result(200, Self.me) == .signedIn(name: "reader", modhash: "hash"))
        #expect(try result(200, "{}") == .signedOut)
        #expect(try result(401, "") == .signedOut)
        #expect(try result(403, "") == .signedOut)
        #expect(try result(200, "<html>Wi-Fi sign-in</html>") == .undetermined)
        #expect(try result(429, "") == .undetermined)
        #expect(try result(500, "{}") == .undetermined)
        let nonHTTP = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(RedditSession.loginCheckResult(data: Data(), response: nonHTTP) == .undetermined)
    }

    @Test("Only the latest check applies, so an older one can't undo a newer result")
    func staleCheckIsIgnored() async throws {
        let gate = Gate()
        let stub = LoginCheckStub([.gated(gate, 200, Self.me), .response(403, "")])
        let session = RedditSession(restoringSession: false, sendLoginCheck: stub.send)
        let older = Task { await session.checkLoginStatus() }
        await gate.waitUntilStarted()

        await session.checkLoginStatus()
        #expect(!session.isLoggedIn)

        gate.open()
        await older.value
        #expect(!session.isLoggedIn)
        #expect(session.username == nil)
    }

    private func cookie() throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [
            .domain: ".reddit.com", .path: "/", .name: "reddit_session", .value: "abc",
        ]))
    }
}

@MainActor
private final class LoginCheckStub {
    enum Reply {
        case response(Int, String)
        case failure(URLError.Code)
        case gated(Gate, Int, String)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
        switch replies.removeFirst() {
        case .failure(let code):
            throw URLError(code)
        case .response(let status, let body):
            return try Self.reply(to: request, status: status, body: body)
        case .gated(let gate, let status, let body):
            await gate.wait()
            return try Self.reply(to: request, status: status, body: body)
        }
    }

    private static func reply(to request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badURL) }
        return (Data(body.utf8), response)
    }
}
