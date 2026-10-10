import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment spoilers")
struct CommentSpoilerTests {
    @Test("Multiple and multiline spoilers retain surrounding prose and stable reveal IDs")
    func partitionsSpoilers() {
        #expect(CommentSpoilers.parse("Before >!first\nsecret!< between >!second!< after") == [
            .text("Before "), .spoiler(id: 0, content: "first\nsecret"),
            .text(" between "), .spoiler(id: 1, content: "second"), .text(" after"),
        ])
        #expect(CommentSpoilers.parse(">!!<") == [.spoiler(id: 0, content: "")])
    }

    @Test("Concealed URLs and embeds never become actionable or loadable body parts")
    func concealsMediaAndLinks() {
        let hidden = "[answer](https://example.com/answer) https://example.com/reveal.png "
            + "https://example.com/reveal.gif ![gif](giphy|secret)"
        #expect(outline("Before >!\(hidden)!< after") == "P(Before) SPOILER(0) P(after)")
    }

    @Test("Reveal enables links and keeps the whole body's single inline GIF budget")
    func revealUsesExistingMediaPolicy() {
        let body = "https://example.com/first.gif >![answer](https://example.com/answer) https://example.com/secret.gif!<"
        #expect(outline(body, revealed: [0])
            == "GIF(https://example.com/first.gif) P([answer](https://example.com/answer)) GIFLINK(https://example.com/secret.gif)")
    }

    @Test("Selective reveal and selection cannot expose another hidden spoiler")
    func sanitizedSelection() {
        let body = "visible >!first secret!< and >!https://example.com/second-secret.png!<"
        #expect(CommentSpoilers.selectionText(from: body, revealed: [])
            == "visible [Spoiler hidden] and [Spoiler hidden]")
        #expect(CommentSpoilers.selectionText(from: body, revealed: [0])
            == "visible first secret and [Spoiler hidden]")
        #expect(outline(body, revealed: [0]) == "P(visible first secret and) SPOILER(1)")
    }

    @Test("Revealed text rejoins its sentence and Markdown before rendering")
    func revealRestoresSurroundingText() {
        #expect(outline("Before >!secret!< after", revealed: [0]) == "P(Before secret after)")
        #expect(outline("**Before >!secret!< after**", revealed: [0]) == "P(**Before secret after**)")
        // An unrevealed spoiler stays a barrier between the visible text around it.
        #expect(outline("Before >!secret!< after >!https://example.com/hidden.png!< end", revealed: [0])
            == "P(Before secret after) SPOILER(1) P(end)")
    }

    @Test("Escaped delimiters stay literal; escaped closing markers do not disclose the suffix")
    func escapedSyntax() {
        let literal = #"before \>!literal!< after"#
        #expect(CommentSpoilers.parse(literal) == [.text(literal)])
        #expect(CommentSpoilers.parse(#">!a \!< still hidden!<"#) == [
            .spoiler(id: 0, content: #"a \!< still hidden"#),
        ])
        #expect(CommentSpoilers.parse(#"\\>!hidden!<"#) == [
            .text(#"\\"#), .spoiler(id: 0, content: "hidden"),
        ])
        #expect(CommentSpoilers.parse(#">\!literal!<"#) == [.text(#">\!literal!<"#)])
    }

    @Test("Unclosed and nested malformed spoilers fail closed, including media")
    func malformedSyntax() {
        #expect(CommentSpoilers.parse("before >!secret https://example.com/image.png") == [
            .text("before "), .spoiler(id: 0, content: "secret https://example.com/image.png"),
        ])
        #expect(CommentSpoilers.parse(">!outer >!inner!< secret!< after") == [
            .spoiler(id: 0, content: "outer >!inner!< secret"), .text(" after"),
        ])
        #expect(CommentSpoilers.selectionText(from: ">!outer >!inner!< secret!< after", revealed: [0])
            == "outer >!inner!< secret after")
        #expect(CommentSpoilers.parse("orphan !< close") == [.text("orphan !< close")])
        #expect(CommentSpoilers.selectionText(from: ">!unclosed", revealed: []) == "[Spoiler hidden]")
    }

    @Test("Unicode boundaries and ordinary Markdown survive spoiler partitioning")
    func preservesOrdinaryContent() {
        #expect(CommentSpoilers.parse("👩🏽‍🚀 >!👨‍👩‍👧‍👦 secret!< café") == [
            .text("👩🏽‍🚀 "), .spoiler(id: 0, content: "👨‍👩‍👧‍👦 secret"), .text(" café"),
        ])
        #expect(outline("# Heading\n> quote\n**bold** and `code`\n---")
            == "H1(Heading) Q[P(quote⏎**bold** and `code`)] RULE")
    }

    @Test("Literal spoiler markers in inline code and fenced code stay literal")
    func codeSyntax() {
        for literal in [
            "`>!literal!<`", "``a ` >!literal!<``",
            "```swift\n>!literal!<\n```", "~~~\n>!literal!<\n~~~",
            "```\n>!unfinished code fence",
        ] {
            #expect(CommentSpoilers.parse(literal) == [.text(literal)])
            #expect(CommentSpoilers.selectionText(from: literal, revealed: []) == literal)
        }
        #expect(CommentSpoilers.parse("`>!literal!<` >!secret!<") == [
            .text("`>!literal!<` "), .spoiler(id: 0, content: "secret"),
        ])
        #expect(CommentSpoilers.parse(">!secret `!<` remains hidden!<") == [
            .spoiler(id: 0, content: "secret `!<` remains hidden"),
        ])
    }

    @Test("CRLF bodies number spoilers the same for rendering and selection")
    func crlfFences() {
        let body = "intro\r\n~~~\r\n>!literal!<\r\n~~~\r\n>!first!<\r\n>!second!<"
        let spoilers = CommentSpoilers.parse(body).compactMap { part -> String? in
            if case .spoiler(_, let content) = part { content } else { nil }
        }
        #expect(spoilers == ["first", "second"])
        let selection = CommentSpoilers.selectionText(from: body, revealed: [1])
        #expect(selection.contains("second"))
        #expect(!selection.contains("first"))
    }

    @Test("An unmatched backtick run cannot become a shorter code opener and expose a spoiler")
    func unmatchedCodeRuns() {
        let body = "`` >!https://example.com/secret.gif!< `"
        #expect(CommentSpoilers.parse(body) == [
            .text("`` "), .spoiler(id: 0, content: "https://example.com/secret.gif"), .text(" `"),
        ])
        #expect(CommentSpoilers.selectionText(from: body, revealed: []) == "`` [Spoiler hidden] `")
        #expect(outline(body) == "P(``) SPOILER(0) P(`)")
    }
}
