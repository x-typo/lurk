import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Thread links")
struct ThreadTargetTests {
    @Test("A comment link, like an inbox Context link, opens that comment's thread")
    func commentLink() throws {
        let url = try #require(URL(string: "https://www.reddit.com/r/HistoryMemes/comments/abc123/every_damn_time/def456/?context=3"))
        let target = try #require(ThreadTarget(url: url))
        #expect(target.postID == "abc123")
        #expect(target.commentID == "def456")
        #expect(target.sourceURL == url)
        #expect(target.wholePost.commentID == nil)
    }

    @Test("Post links and relative permalinks open the whole thread")
    func postLinks() throws {
        let postURL = try #require(URL(string: "https://old.reddit.com/r/swift/comments/abc123/a_post/"))
        let post = try #require(ThreadTarget(url: postURL))
        #expect(post.postID == "abc123")
        #expect(post.commentID == nil)

        let permalink = try #require(ThreadTarget(permalink: "/r/swift/comments/abc123/a_post/def456/"))
        #expect(permalink.postID == "abc123")
        #expect(permalink.commentID == "def456")

        let short = try #require(ThreadTarget(permalink: "/comments/abc123/"))
        #expect(short.postID == "abc123")
        #expect(short.commentID == nil)
    }

    @Test("Links that aren't Reddit threads stay in the browser")
    func rejectsOtherLinks() throws {
        for link in [
            "https://example.com/r/swift/comments/abc123/a_post/",
            "https://www.reddit.com/r/swift/",
            "https://www.reddit.com/r/swift/comments/ABC/a_post/",
            "https://www.reddit.com/r/swift/comments/../a_post/",
        ] {
            let url = try #require(URL(string: link))
            #expect(ThreadTarget(url: url) == nil, "\(link)")
        }
    }
}
