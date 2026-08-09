import Foundation
import Testing
@testable import Lurk

@Suite("Reddit API response summaries")
struct RedditAPIResponseSummaryTests {
    @Test("A message takes precedence over a numeric error")
    func prefersMessage() {
        let data = Data(#"{"message":"rate limited","error":403}"#.utf8)
        #expect(RedditAPI.responseSummary(from: data) == "rate limited")
    }

    @Test("A scalar error is converted to text")
    func summarizesScalarError() {
        let data = Data(#"{"error":403}"#.utf8)
        #expect(RedditAPI.responseSummary(from: data) == "403")
    }

    @Test("Reddit validation errors are flattened and empty entries are ignored")
    func summarizesValidationErrors() {
        let data = Data(
            #"{"json":{"errors":[["RATELIMIT","slow down","field"],["","",""]]}}"#.utf8
        )
        #expect(RedditAPI.responseSummary(from: data) == "RATELIMIT: slow down: field")
    }

    @Test("HTML is stripped and whitespace is collapsed")
    func summarizesHTML() {
        let data = Data(" <html>\n<p> Service   unavailable </p>\n</html> ".utf8)
        #expect(RedditAPI.responseSummary(from: data) == "Service unavailable")
    }

    @Test("Reddit's network-security response gets a stable message")
    func normalizesNetworkSecurityMessage() {
        let data = Data("You've been blocked by network security".utf8)
        #expect(
            RedditAPI.responseSummary(from: data)
                == "You've been blocked by Reddit network security."
        )
    }

    @Test("An empty response has no summary")
    func ignoresEmptyResponse() {
        #expect(RedditAPI.responseSummary(from: Data()) == nil)
    }
}
