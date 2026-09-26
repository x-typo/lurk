import Foundation
import Testing
@testable import Lurk

@Suite("Reddit listing decoding")
struct RedditListingDecodingTests {
    @Test("Malformed children are dropped when a page also contains a valid post")
    func preservesValidChildren() throws {
        let listing = try RedditAPI.decoder.decode(RedditListing.self, from: mixedListingData)

        #expect(listing.data.after == "t3_after")
        #expect(listing.data.children.count == 1)

        let post = try #require(listing.data.children.first?.data)
        #expect(post.id == "valid")
        #expect(post.subredditNamePrefixed == "r/swift")
        #expect(post.numComments == 12)
        #expect(post.createdUtc == 1_700_000_000)
        #expect(post.over18 == false)
    }

    @MainActor
    @Test("The viewer's vote and saved state decode, and the score counts the vote once")
    func viewerStateDecodes() throws {
        let upvoted = try post(extraFields: #""likes": true, "saved": true,"#)
        #expect(upvoted.initialVote == 1)
        #expect(upvoted.saved)
        #expect(upvoted.displayScore(vote: 1) == 42)
        #expect(upvoted.displayScore(vote: 0) == 41)
        #expect(upvoted.displayScore(vote: -1) == 40)

        let downvoted = try post(extraFields: #""likes": false,"#)
        #expect(downvoted.initialVote == -1)

        let anonymous = try post(extraFields: #""likes": null,"#)
        #expect(anonymous.initialVote == 0)
        #expect(!anonymous.saved)
    }

    @Test("A nonempty page where every child is malformed is rejected")
    func rejectsAllMalformedChildren() {
        #expect(throws: DecodingError.self) {
            try RedditAPI.decoder.decode(RedditListing.self, from: invalidListingData)
        }
    }

    private var mixedListingData: Data {
        Data(
            #"""
            {
              "data": {
                "after": "t3_after",
                "children": [
                  {
                    "data": {
                      "id": "valid",
                      "title": "A valid post",
                      "author": "reader",
                      "subreddit": "swift",
                      "subreddit_name_prefixed": "r/swift",
                      "score": 42,
                      "num_comments": 12,
                      "created_utc": 1700000000,
                      "permalink": "/r/swift/comments/valid/a_valid_post/",
                      "url": "https://example.com/article",
                      "selftext": "",
                      "is_self": false,
                      "is_video": false,
                      "stickied": false,
                      "over_18": false
                    }
                  },
                  {
                    "data": {
                      "id": "incomplete"
                    }
                  }
                ]
              }
            }
            """#.utf8
        )
    }

    private func post(extraFields: String) throws -> Post {
        let data = Data(
            """
            {"data": {"after": null, "children": [{"data": {
              \(extraFields)
              "id": "voted", "title": "A post", "author": "reader", "subreddit": "swift",
              "subreddit_name_prefixed": "r/swift", "score": 42, "num_comments": 1,
              "created_utc": 1700000000, "permalink": "/r/swift/comments/voted/a_post/",
              "url": "https://example.com", "selftext": "", "is_self": false, "is_video": false,
              "stickied": false, "over_18": false
            }}]}}
            """.utf8
        )
        return try #require(RedditAPI.decoder.decode(RedditListing.self, from: data).data.children.first?.data)
    }

    private var invalidListingData: Data {
        Data(
            #"""
            {
              "data": {
                "after": null,
                "children": [
                  {
                    "data": {
                      "id": "incomplete"
                    }
                  }
                ]
              }
            }
            """#.utf8
        )
    }
}
