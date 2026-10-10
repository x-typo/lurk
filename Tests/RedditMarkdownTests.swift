import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Reddit Markdown blocks")
struct RedditMarkdownTests {
    // Reconstructed from r/anime's episode-discussion template (r/anime blcjwm) and the owner's screenshots.
    private static let episodeDiscussion = """
    *Dororo*, episode 17

    #[Rate this episode here.](https://www.reddit.com/r/anime/wiki/rating)

    ---

    **Reminder:** Please do not discuss plot points not yet seen or skipped in the show.

    **Streams**

    * [Amazon US](https://www.amazon.com/dp/B07N)
    * [Amazon UK](https://www.amazon.co.uk/dp/B07N)

    **Previous discussions**

    Episode|Link|Score
    :-:|:-:|:-:
    1|[Link](https://redd.it/ad7w0h)|[9.07](https://redd.it/ad7w0h)
    2|[Link](https://redd.it/afh8bn)|[9.24](https://redd.it/afh8bn)
    """

    @Test("An episode discussion keeps its heading, list, and table with their links")
    func episodeDiscussionStructure() throws {
        let parts = CommentBodyView.parse(Self.episodeDiscussion)
        guard parts.count == 1, case .text(let text) = parts[0] else {
            Issue.record("Ordinary links split the body into \(parts.count) parts")
            return
        }

        let blocks = RedditMarkdown.blocks(from: text)
        #expect(blocks.count == 8)
        guard blocks.count == 8 else { return }

        guard case .heading(1, let heading) = blocks[1] else {
            Issue.record("Expected \"#[Rate this episode here.](…)\" to be a heading, got \(blocks[1])")
            return
        }
        #expect(String(heading.characters) == "Rate this episode here.")
        #expect(heading.runs.first?.link?.absoluteString == "https://www.reddit.com/r/anime/wiki/rating")
        #expect(blocks[2] == .rule)

        guard case .list(false, let items) = blocks[5] else {
            Issue.record("Expected the streams to be a bulleted list, got \(blocks[5])")
            return
        }
        #expect(items.count == 2)
        guard case .paragraph(let first) = items.first?.blocks.first else {
            Issue.record("Expected a list item's text")
            return
        }
        #expect(String(first.characters) == "Amazon US")
        #expect(first.runs.first?.link?.host() == "www.amazon.com")

        guard case .table(let table) = blocks[7] else {
            Issue.record("Expected the previous discussions to be a table, got \(blocks[7])")
            return
        }
        #expect(table.alignments == [.center, .center, .center])
        #expect(table.header.map { String($0.characters) } == ["Episode", "Link", "Score"])
        #expect(table.rows.count == 2)
        #expect(table.rows.first?.map { String($0.characters) } == ["1", "Link", "9.07"])
        #expect(table.rows.first?[2].runs.first?.link?.absoluteString == "https://redd.it/ad7w0h")
    }

    @Test("Reddit headings without a space become headings, except in code and table rows")
    func compactHeadings() {
        #expect(RedditMarkdown.normalized("#Title\n##  Sub") == "# Title\n##  Sub")
        #expect(RedditMarkdown.normalized("#Episode 5 | Discussion\n\ntext") == "# Episode 5 | Discussion\n\ntext")
        #expect(RedditMarkdown.normalized("####### seven") == "####### seven")
        for unchanged in [
            "```\n#include <stdio.h>\n```",
            "```npm i```\n\n```\n#include <stdio.h>\n```",
            "* ```\n  #!/bin/bash\n  ```",
            "```\n#a\n```py\n#b\n```",
            "#|Name\n-|-\n1|Ty",
            "Rank|Team\n-|-\n#1|Foo\n#2|Bar",
        ] {
            #expect(RedditMarkdown.normalized(unchanged) == unchanged)
        }
        // A row needs a pipe, so a heading right after a table, or after a fenced table example, still counts.
        #expect(RedditMarkdown.normalized("A|B\n-|-\n#Next") == "A|B\n-|-\n# Next")
        #expect(RedditMarkdown.normalized("```\nA|B\n-|-\n```\n#Next") == "```\nA|B\n-|-\n```\n# Next")
        // Fences indented, inside a quoted list item, or with tab-indented lines still shelter "#" lines.
        #expect(RedditMarkdown.normalized("  ~~~\n  #x\n~~~\n#Next") == "  ~~~\n  #x\n~~~\n# Next")
        for unchanged in ["- > ~~~\n  > #x\n  > ~~~", "- ~~~\n\t#x\n  ~~~"] {
            #expect(RedditMarkdown.normalized(unchanged) == unchanged)
        }
    }

    @Test("Block HTML keeps its place, including inside quotes and list items")
    func blockHTMLStaysInPlace() {
        #expect(texts(RedditMarkdown.blocks(from: "Sure, that will totally work.\n\n</s>\n\nEdit: thanks")) == [
            "Sure, that will totally work.", "</s>", "Edit: thanks",
        ])
        guard case .quote(let quoted) = RedditMarkdown.blocks(from: "> <rant>\n> quoted rant\n> </rant>").first else {
            Issue.record("Expected a quote")
            return
        }
        #expect(texts(quoted) == ["<rant>\nquoted rant\n</rant>"])
        guard case .list(false, let items) = RedditMarkdown.blocks(from: "- <sarcasm>\n- second").first else {
            Issue.record("Expected a bulleted list")
            return
        }
        #expect(items.map { texts($0.blocks) } == [["<sarcasm>"], ["second"]])
    }

    @Test("Regressions from the sweep against main stay fixed")
    func sweepRegressions() {
        // An image URL in fenced code stays in the code; the text after the block stays prose.
        let fenced = CommentBodyView.parse("```\ncurl -O https://example.com/banner.jpg\n```\n\nThen run it again.")
        guard fenced.count == 1, case .text(let fencedText) = fenced[0] else {
            Issue.record("Expected one text part, got \(fenced)")
            return
        }
        #expect(texts(RedditMarkdown.blocks(from: fencedText)) == ["Then run it again."])

        // A lone quote marker before media draws nothing.
        #expect(RedditMarkdown.blocks(from: "> ").isEmpty)
        #expect(RedditMarkdown.blocks(from: "\n> ", continuingLine: true).isEmpty)

        // A revealed spoiler at a line start stays prose.
        let revealed = CommentBodyView.parse(">!#1 is Naruto!<", revealedSpoilers: [0])
        guard revealed.count == 1, case .text(let revealedText) = revealed[0] else {
            Issue.record("Expected one text part, got \(revealed)")
            return
        }
        #expect(texts(RedditMarkdown.blocks(from: revealedText)) == ["#1 is Naruto"])

        // A giphy embed under a table plays instead of joining it as a row.
        let underTable = CommentBodyView.parse("Arc|Episodes\n:--|--:\nOpening|1-6\n![gif](giphy|abc123)")
        #expect(underTable.contains { if case .gif = $0 { true } else { false } })

        // Markdown in and after a block HTML line still renders inline.
        guard case .paragraph(let html) = RedditMarkdown.blocks(from: "<sarcasm>\nYeah **that** works, see https://example.com/x\n</sarcasm>").first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(!String(html.characters).contains("**"))
        #expect(html.runs.contains { $0.link?.absoluteString == "https://example.com/x" })

        // A caret before a link keeps both.
        guard case .paragraph(let caret) = RedditMarkdown.blocks(from: "Sources say so^[1](https://example.com/src) and more").first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(String(caret.characters) == "Sources say so^1 and more")
        #expect(caret.runs.contains { $0.link?.absoluteString == "https://example.com/src" })

        // A regex in code keeps its caret, and an unclosed top-level fence still shelters "#!/bin/sh".
        #expect(RedditMarkdown.normalized("Use `^[a-z]+` here") == "Use `^[a-z]+` here")
        #expect(RedditMarkdown.normalized("```sh\n#!/bin/sh") == "```sh\n#!/bin/sh")

        // An image-style link to a page in block HTML stays tappable.
        guard case .paragraph(let htmlImage) = RedditMarkdown.blocks(from: "<rant>\n![clip](https://example.com/watch)\n</rant>").first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(htmlImage.runs.contains { $0.link?.absoluteString == "https://example.com/watch" })

        // A link keeps its target across a line break in its text, with a space in its address, and with a title.
        for (body, words, address) in [
            ("Read [the full\nannouncement](https://example.com/news) here", "the full announcement", "https://example.com/news"),
            ("[y](https://example.com/c d)", "y", "https://example.com/c%20d"),
            ("[label](https://example.com/page (title))", "label", "https://example.com/page"),
        ] {
            let parts = CommentBodyView.parse(body)
            guard parts.count == 1, case .text(let text) = parts[0],
                  case .paragraph(let paragraph) = RedditMarkdown.blocks(from: text).first else {
                Issue.record("Expected one paragraph for \(body), got \(parts)")
                continue
            }
            #expect(paragraph.runs.contains { run in
                run.link?.absoluteString == address && String(paragraph[run.range].characters) == words
            })
        }
    }

    @Test("Text after media or a hidden spoiler on the same line stays prose")
    func continuedLines() {
        for (text, expected) in [
            (" - my desk setup", "- my desk setup"),
            (" #2 is my favorite", "#2 is my favorite"),
            (" 1. weird", "1. weird"),
        ] {
            #expect(texts(RedditMarkdown.blocks(from: text, continuingLine: true)) == [expected])
        }
        // Inline emphasis isn't a block marker.
        for (text, expected) in [(" **important** stuff", "important stuff"), (" *italic* stuff", "italic stuff")] {
            guard case .paragraph(let paragraph) = RedditMarkdown.blocks(from: text, continuingLine: true).first else {
                Issue.record("Expected a paragraph for \(text)")
                continue
            }
            #expect(String(paragraph.characters) == expected)
            #expect(paragraph.runs.contains { $0.inlinePresentationIntent != nil })
        }
        guard case .list = RedditMarkdown.blocks(from: "\n- next line", continuingLine: true).first else {
            Issue.record("A list on the next line should stay a list")
            return
        }
    }

    @Test("A lone list or heading marker is shown as written")
    func loneMarkers() {
        for marker in ["2. ", "-", "#"] {
            #expect(texts(RedditMarkdown.blocks(from: marker)) == [marker.trimmingCharacters(in: .whitespaces)])
        }
    }

    @Test("An image link to a page that isn't an image keeps its link")
    func imageSyntaxLink() {
        guard case .paragraph(let text) = RedditMarkdown.blocks(from: "See ![the clip](https://streamable.com/abc) lol").first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(text.runs.contains { $0.link?.absoluteString == "https://streamable.com/abc" })
    }

    @Test("Single newlines stay line breaks, and ordered and nested lists keep their numbers")
    func lineBreaksAndLists() {
        let blocks = RedditMarkdown.blocks(from: "first line\nsecond line\n\n3. third\n4. fourth\n   * nested")
        guard blocks.count == 2, case .paragraph(let paragraph) = blocks[0],
              case .list(true, let items) = blocks[1] else {
            Issue.record("Unexpected blocks: \(blocks)")
            return
        }
        #expect(String(paragraph.characters) == "first line\nsecond line")
        #expect(items.map(\.ordinal) == [3, 4])
        guard case .list(false, let nested) = items.last?.blocks.last else {
            Issue.record("Expected a nested bulleted list")
            return
        }
        #expect(nested.count == 1)
    }

    @Test("Ordinary links stay in the prose instead of splitting it")
    func linksStayInline() {
        expectOneTextPart("See [the wiki](https://example.com/wiki) or https://example.com/faq, then reply.")
    }

    @Test("Media in a list item or table row stays a link; media in prose still embeds")
    func mediaInsideBlocks() {
        for body in [
            "* [screenshot](https://example.com/shot.png)",
            "1. https://example.com/loop.gif",
            "Name|Picture\n-|-\nTy|[pic](https://example.com/ty.png)",
            "```\nA|B\n-|-\nx|[pic](https://example.com/p.png)\n```",
        ] {
            expectOneTextPart(body)
        }

        // CRLF line breaks still mark a list item's line.
        let crlf = CommentBodyView.parse("intro\r\n* [pic](https://example.com/p.png)")
        guard crlf.count == 1, case .text(let crlfText) = crlf[0] else {
            Issue.record("Expected one text part, got \(crlf)")
            return
        }
        #expect(crlfText == "intro\n* [pic](https://example.com/p.png)")

        // A giphy embed kept in a list becomes a link to the GIF.
        let listGiphy = CommentBodyView.parse("* ![gif](giphy|abc)")
        guard listGiphy.count == 1, case .text(let listText) = listGiphy[0] else {
            Issue.record("Expected one text part, got \(listGiphy)")
            return
        }
        #expect(listText == "* [gif](https://media.giphy.com/media/abc/giphy.gif)")

        // An embed after a quoted code block still plays.
        let afterQuotedCode = CommentBodyView.parse("> ~~~\n> code\n\n![gif](giphy|abc)")
        #expect(afterQuotedCode.contains { if case .gif = $0 { true } else { false } })

        // Only a table's own rows keep media as links; an embed after the table still plays.
        let afterTable = CommentBodyView.parse("A|B\n-|-\n1|2\n\n![gif](giphy|abc)")
        #expect(afterTable.contains { if case .gif = $0 { true } else { false } })

        let prose = CommentBodyView.parse("Look https://example.com/shot.png wow")
        guard prose.count == 3, case .image = prose[1] else {
            Issue.record("Expected an image in prose to embed, got \(prose)")
            return
        }
    }

    private func texts(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.compactMap { block in
            if case .paragraph(let text) = block { String(text.characters) } else { nil }
        }
    }

    private func expectOneTextPart(_ body: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let parts = CommentBodyView.parse(body)
        guard parts.count == 1, case .text(let text) = parts[0] else {
            Issue.record("Expected one text part, got \(parts)", sourceLocation: sourceLocation)
            return
        }
        #expect(text == body, sourceLocation: sourceLocation)
    }
}
