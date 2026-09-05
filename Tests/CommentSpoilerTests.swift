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
        let parts = CommentBodyView.displayParts(from: "Before >!\(hidden)!< after")
        #expect(parts.count == 3)
        guard parts.count == 3, case .text("Before ") = parts[0],
              case .spoiler(0, let content) = parts[1], case .text(" after") = parts[2] else {
            Issue.record("Hidden content escaped into the visible body parser")
            return
        }
        #expect(content == hidden)
    }

    @Test("Reveal enables links and keeps the whole body's single inline GIF budget")
    func revealUsesExistingMediaPolicy() {
        let parts = CommentBodyView.displayParts(
            from: "https://example.com/first.gif >![answer](https://example.com/answer) "
                + "https://example.com/secret.gif!<",
            revealedSpoilers: [0]
        )
        #expect(parts.filter { if case .gif = $0 { true } else { false } }.count == 1)
        #expect(parts.contains { if case .link("answer", _) = $0 { true } else { false } })
        #expect(parts.contains {
            if case .link("Open GIF", let url) = $0 { url.lastPathComponent == "secret.gif" } else { false }
        })
        #expect(!parts.contains { if case .spoiler = $0 { true } else { false } })
    }

    @Test("Selective reveal and selection cannot expose another hidden spoiler")
    func sanitizedSelection() {
        let body = "visible >!first secret!< and >!https://example.com/second-secret.png!<"
        #expect(CommentSpoilers.selectionText(from: body, revealed: [])
            == "visible [Spoiler hidden] and [Spoiler hidden]")
        #expect(CommentSpoilers.selectionText(from: body, revealed: [0])
            == "visible first secret and [Spoiler hidden]")
        let parts = CommentBodyView.parse(body, revealedSpoilers: [0])
        #expect(parts.contains { if case .spoiler(1, _) = $0 { true } else { false } })
        #expect(!parts.contains { if case .image = $0 { true } else { false } })
    }

    @Test("Revealed text rejoins its sentence and Markdown before rendering")
    func revealRestoresSurroundingText() {
        for (body, expected) in [
            ("Before >!secret!< after", "Before secret after"),
            ("**Before >!secret!< after**", "**Before secret after**"),
        ] {
            let parts = CommentBodyView.parse(body, revealedSpoilers: [0])
            guard parts.count == 1, case .text(let text) = parts[0] else {
                Issue.record("Revealing a spoiler should restore one continuous text segment")
                continue
            }
            #expect(text == expected)
        }

        let partial = CommentBodyView.parse(
            "Before >!secret!< after >!https://example.com/hidden.png!< end",
            revealedSpoilers: [0]
        )
        guard partial.count == 3, case .text("Before secret after ") = partial[0],
              case .spoiler(1, _) = partial[1], case .text(" end") = partial[2] else {
            Issue.record("An unrevealed spoiler must remain a barrier between visible segments")
            return
        }
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
        let ordinary = "# Heading\n> quote\n**bold** and `code`\n---"
        let parts = CommentBodyView.parse(ordinary)
        guard parts.count == 1, case .text(let text) = parts[0] else {
            Issue.record("Ordinary Markdown was unexpectedly split")
            return
        }
        #expect(text == ordinary)
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

    @Test("An unmatched backtick run cannot become a shorter code opener and expose a spoiler")
    func unmatchedCodeRuns() {
        let body = "`` >!https://example.com/secret.gif!< `"
        #expect(CommentSpoilers.parse(body) == [
            .text("`` "), .spoiler(id: 0, content: "https://example.com/secret.gif"), .text(" `"),
        ])
        #expect(CommentSpoilers.selectionText(from: body, revealed: []) == "`` [Spoiler hidden] `")
        let parts = CommentBodyView.displayParts(from: body)
        #expect(!parts.contains { if case .gif = $0 { true } else { false } })
        #expect(parts.contains { if case .spoiler = $0 { true } else { false } })
    }
}
