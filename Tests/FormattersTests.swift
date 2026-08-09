import Testing
@testable import Lurk

@Suite("Formatters")
struct FormattersTests {
    @Test("Scores use compact suffixes at stable thresholds")
    func formatsScores() {
        #expect(Formatters.score(-5) == "-5")
        #expect(Formatters.score(999) == "999")
        #expect(Formatters.score(1_000) == "1.0k")
        #expect(Formatters.score(1_500) == "1.5k")
        #expect(Formatters.score(1_000_000) == "1.0M")
        #expect(Formatters.score(1_500_000) == "1.5M")
    }
}
