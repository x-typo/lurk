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

    @Test("A lurk:// link opens its Reddit thread, as Rakuroku's discussion links send it")
    func lurkLinks() throws {
        let rakuroku = try #require(URL(string: "lurk://open?url=https%3A%2F%2Fwww.reddit.com%2Fr%2Fanime%2Fcomments%2F1nss3jv%2Fone_piece_episode_1145_discussion%2F"))
        let threadURL = try #require(URL(string: "https://www.reddit.com/r/anime/comments/1nss3jv/one_piece_episode_1145_discussion/"))
        #expect(LurkLink(rakuroku) == .thread(ThreadTarget(postID: "1nss3jv", sourceURL: threadURL)))

        for thread in [
            "https://reddit.com/r/anime/comments/1nss3jv/",
            "https://old.reddit.com/r/anime/comments/1nss3jv/one_piece_episode_1145_discussion",
            "https://www.reddit.com/r/anime/comments/1nss3jv/one_piece_episode_1145_discussion/?utm_source=share",
        ] {
            let link = try #require(lurkLink(thread))
            let url = try #require(URL(string: thread))
            #expect(LurkLink(link) == .thread(ThreadTarget(postID: "1nss3jv", sourceURL: url)), "\(thread)")
        }
    }

    @Test("Other Reddit links in a lurk:// link go to the browser, since the sender can't fall back once Lurk takes the scheme")
    func sendsOtherRedditLinksToBrowser() throws {
        for other in [
            "https://np.reddit.com/r/anime/comments/1nss3jv/",
            "https://www.reddit.com/r/anime/",
            "https://www.reddit.com/user/someone/comments/1nss3jv/",
            "https://www.reddit.com/r/anime/comments/1nss3jv/slug/def456/",
            "https://www.reddit.com/r/anime/comments/NOT-AN-ID/",
            "https://redd.it/1nss3jv",
        ] {
            let link = try #require(lurkLink(other))
            let url = try #require(URL(string: other))
            #expect(LurkLink(link) == .web(url), "\(other)")
        }
    }

    @Test("A lurk:// link to anything but an https Reddit link is ignored")
    func ignoresOtherLurkLinks() throws {
        for other in [
            "http://www.reddit.com/r/anime/comments/1nss3jv/",
            "https://example.com/r/anime/comments/1nss3jv/",
            "https://reddit.com.example.com/r/anime/comments/1nss3jv/",
            "https://notreddit.com/r/anime/comments/1nss3jv/",
            "not a url",
        ] {
            let link = try #require(lurkLink(other))
            #expect(LurkLink(link) == nil, "\(other)")
        }
        for link in [
            "lurk://open",
            "lurk://open?url=",
            "lurk://open?link=https%3A%2F%2Fwww.reddit.com%2Fr%2Fanime%2Fcomments%2F1nss3jv%2F",
            "lurk://thread?url=https%3A%2F%2Fwww.reddit.com%2Fr%2Fanime%2Fcomments%2F1nss3jv%2F",
            "https://www.reddit.com/r/anime/comments/1nss3jv/",
        ] {
            let url = try #require(URL(string: link))
            #expect(LurkLink(url) == nil, "\(link)")
        }
    }

    private func lurkLink(_ thread: String) -> URL? {
        var components = URLComponents()
        components.scheme = "lurk"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: thread)]
        return components.url
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

        let named = try #require(ThreadTarget(permalink: "/r/comments/comments/abc123/a_post/def456/"))
        #expect(named.postID == "abc123")
        #expect(named.commentID == "def456")

        let profile = try #require(ThreadTarget(permalink: "/user/someone/comments/abc123/a_post/"))
        #expect(profile.postID == "abc123")

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
            "https://www.reddit.com/r/swift/about/comments/abc123/",
        ] {
            let url = try #require(URL(string: link))
            #expect(ThreadTarget(url: url) == nil, "\(link)")
        }
    }
}
