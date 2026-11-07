import Foundation
import Testing
@testable import Lurk

@Suite("Reply request")
@MainActor
struct ReplyRequestTests {
    @Test("Replies ask Reddit to report refusals in the JSON envelope the client checks")
    func replyAsksForJSONErrors() throws {
        let request = RedditSession(restoringSession: false).authenticatedRequest(
            url: RedditAPI.comment,
            formData: ComposeReplySheet.formData(thingID: "t1_abc", text: "Nice & tidy")
        )

        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(request.url == RedditAPI.comment)
        #expect(request.httpMethod == "POST")
        #expect(formFields(body) == ["thing_id": "t1_abc", "text": "Nice & tidy", "api_type": "json"])
    }

    private func formFields(_ body: String) -> [String: String] {
        let decode = { (value: Substring) in
            value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(value)
        }
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
        })
    }
}
