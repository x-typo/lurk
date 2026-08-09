import Testing
@testable import Lurk

@Suite("Subreddit names")
struct SubredditNameTests {
    @Test("Names are trimmed and an r slash prefix is removed case-insensitively")
    func normalizesNames() {
        #expect(SubredditName.normalize("  R/Swift_UI\n") == "Swift_UI")
        #expect(SubredditName.canonicalKey(" r/Swift_UI ") == "swift_ui")
    }

    @Test("Only Reddit's supported name shape is accepted")
    func rejectsInvalidNames() {
        for value in ["", "r/", "x", "swift-ui", "r/r/swift", "has space"] {
            #expect(SubredditName.normalize(value) == nil)
        }
    }

    @Test("Length boundaries are enforced")
    func enforcesLengthBoundaries() {
        #expect(SubredditName.normalize("ab") == "ab")
        #expect(SubredditName.normalize(String(repeating: "a", count: 21)) != nil)
        #expect(SubredditName.normalize("a") == nil)
        #expect(SubredditName.normalize(String(repeating: "a", count: 22)) == nil)
    }
}
