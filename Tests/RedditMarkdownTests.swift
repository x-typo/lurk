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

    @Test("Text after media or a hidden spoiler on the same line stays prose")
    func continuedLines() {
        for (text, expected) in [
            (" - my desk setup", "- my desk setup"),
            (" #2 is my favorite", "#2 is my favorite"),
            (" 1. weird", "1. weird"),
        ] {
            #expect(texts(RedditMarkdown.blocks(from: text, continuingLine: true)) == [expected])
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
        ] {
            expectOneTextPart(body)
        }

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
