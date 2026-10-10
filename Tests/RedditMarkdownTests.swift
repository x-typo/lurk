import Foundation
import Testing
@testable import Lurk

// A compact, exact outline of a body's blocks, such as "P(Look) IMG(https://…) P(wow)": links show as
// [text](url), inline code as `code`, bold as **text**, italics as _text_, and line breaks as ⏎.
func outline(_ text: String, revealed: Set<Int> = []) -> String {
    outline(RedditMarkdown.blocks(from: text, revealedSpoilers: revealed))
}

func outline(_ blocks: [MarkdownBlock]) -> String {
    func inline(_ text: AttributedString) -> String {
        text.runs.map { run in
            var piece = String(text[run.range].characters).replacingOccurrences(of: "\n", with: "⏎")
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { piece = "`\(piece)`" }
            if intent.contains(.stronglyEmphasized) { piece = "**\(piece)**" }
            if intent.contains(.emphasized) { piece = "_\(piece)_" }
            return run.link.map { "[\(piece)](\($0.absoluteString))" } ?? piece
        }.joined()
    }
    return blocks.map { block in
        switch block {
        case .paragraph(let text): "P(\(inline(text)))"
        case .heading(let level, let text): "H\(level)(\(inline(text)))"
        case .quote(let blocks): "Q[\(outline(blocks))]"
        case .list(let ordered, let items):
            (ordered ? "OL" : "UL") + "[" + items.map { "\($0.ordinal):" + outline($0.blocks) }.joined(separator: "; ") + "]"
        case .code(let code): "CODE(\(code.replacingOccurrences(of: "\n", with: "⏎")))"
        case .table(let table):
            "TABLE(" + ([table.header] + table.rows).map { $0.map(inline).joined(separator: "|") }.joined(separator: " / ") + ")"
        case .rule: "RULE"
        case .image(let url): "IMG(\(url.absoluteString))"
        case .gif(let url): "GIF(\(url.absoluteString))"
        case .gifLink(let url): "GIFLINK(\(url.absoluteString))"
        case .spoiler(let id): "SPOILER(\(id))"
        }
    }.joined(separator: " ")
}

@MainActor
@Suite("Reddit Markdown blocks")
struct RedditMarkdownTests {
    // Reconstructed from r/anime's episode-discussion template (r/anime blcjwm) and the owner's screenshots.
    private static let episodeDiscussion = """
    *Dororo*, episode 17

    #[Rate this episode here.](https://www.reddit.com/r/anime/wiki/rating)

    ---

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
    func episodeDiscussionStructure() {
        #expect(outline(Self.episodeDiscussion) == [
            "P(_Dororo_, episode 17)",
            "H1([Rate this episode here.](https://www.reddit.com/r/anime/wiki/rating))",
            "RULE",
            "P(**Streams**)",
            "UL[1:P([Amazon US](https://www.amazon.com/dp/B07N)); 2:P([Amazon UK](https://www.amazon.co.uk/dp/B07N))]",
            "P(**Previous discussions**)",
            "TABLE(Episode|Link|Score / 1|[Link](https://redd.it/ad7w0h)|[9.07](https://redd.it/ad7w0h)"
                + " / 2|[Link](https://redd.it/afh8bn)|[9.24](https://redd.it/afh8bn))",
        ].joined(separator: " "))
        guard case .table(let table) = RedditMarkdown.blocks(from: Self.episodeDiscussion).last else {
            Issue.record("Expected a table last")
            return
        }
        #expect(table.alignments == [.center, .center, .center])
    }

    @Test("Reddit's \"#Title\" is a heading at the top level, and code keeps its bytes")
    func compactHeadings() {
        #expect(outline("#Title\n##  Sub\ntext\n#Second") == "H1(Title) H2(Sub) P(text) H1(Second)")
        #expect(outline("A|B\n-|-\n#Next") == "TABLE(A|B) H1(Next)")
        #expect(outline("```\n#include <stdio.h>\n```\n\n    #indented\n\n`#inline`")
            == "CODE(#include <stdio.h>) CODE(#indented) P(`#inline`)")
        #expect(outline("#|Name\n-|-\n1|Ty") == "TABLE(#|Name / 1|Ty)")
        #expect(outline("Rank|Team\n-|-\n#1|Foo") == "TABLE(Rank|Team / #1|Foo)")
        #expect(outline("\\#1 fan of this show") == "P(#1 fan of this show)")
        #expect(outline("####### seven") == "P(####### seven)")
        // Accepted: a compact heading with a pipe, or inside a quote or list, stays as written, as on main.
        #expect(outline("#Episode 5 | Discussion") == "P(#Episode 5 | Discussion)")
    }

    @Test("Single newlines stay line breaks, and ordered and nested lists keep their numbers")
    func lineBreaksAndLists() {
        #expect(outline("first line\nsecond line\n\n3. third\n4. fourth\n   * nested")
            == "P(first line⏎second line) OL[3:P(third); 4:P(fourth) UL[1:P(nested)]]")
    }

    @Test("Block HTML keeps its place and its inline Markdown")
    func blockHTML() {
        #expect(outline("Sure, that will totally work.\n\n</s>\n\nEdit: thanks")
            == "P(Sure, that will totally work.) P(</s>) P(Edit: thanks)")
        #expect(outline("> <rant>\n> quoted rant\n> </rant>") == "Q[P(<rant>⏎quoted rant⏎</rant>)]")
        #expect(outline("- <sarcasm>\n- second") == "UL[1:P(<sarcasm>); 2:P(second)]")
        #expect(outline("<rant>\nYeah **that** works, see https://example.com/x\n![clip](https://example.com/watch)\n</rant>")
            == "P(<rant>⏎Yeah **that** works, see [https://example.com/x](https://example.com/x)⏎[clip](https://example.com/watch)⏎</rant>)")
    }

    @Test("Links stay inline, including image syntax to a page, titles, and carets")
    func links() {
        #expect(outline("See [the wiki](https://example.com/wiki) or https://example.com/faq, then reply.")
            == "P(See [the wiki](https://example.com/wiki) or [https://example.com/faq](https://example.com/faq), then reply.)")
        #expect(outline("See ![the clip](https://streamable.com/abc) lol") == "P(See [the clip](https://streamable.com/abc) lol)")
        #expect(outline("[label](https://example.com/page (title))") == "P([label](https://example.com/page))")
        #expect(outline("Sources say so^[1](https://example.com/src) and more, `^[a-z]+`")
            == "P(Sources say so^[1](https://example.com/src) and more, `^[a-z]+`)")
    }

    @Test("Images and GIFs lift out of prose and quotes, and stay links in lists, headings, and tables")
    func media() {
        #expect(outline("Look https://example.com/shot.png wow") == "P(Look) IMG(https://example.com/shot.png) P(wow)")
        #expect(outline("Here:\nhttps://example.com/x.png\nCool right?") == "P(Here:) IMG(https://example.com/x.png) P(Cool right?)")
        #expect(outline("> https://example.com/q.png") == "Q[IMG(https://example.com/q.png)]")
        #expect(outline("* ![gif](giphy|abc)\n* [pic](https://example.com/p.png)")
            == "UL[1:P([gif](https://media.giphy.com/media/abc/giphy.gif)); 2:P([pic](https://example.com/p.png))]")
        #expect(outline("A|B\n-|-\n1|![gif](giphy|abc|downsized)\n\n![gif](giphy|def)")
            == "TABLE(A|B / 1|[gif](https://media.giphy.com/media/abc/giphy.gif)) GIF(https://media.giphy.com/media/def/giphy.gif)")
        #expect(outline("```\ncurl -O https://example.com/banner.jpg\n```\n\nThen run it again.")
            == "CODE(curl -O https://example.com/banner.jpg) P(Then run it again.)")
        #expect(outline("> ~~~\n> code\n\n![gif](giphy|abc)") == "Q[CODE(code)] GIF(https://media.giphy.com/media/abc/giphy.gif)")
        #expect(outline("intro\r\n* [pic](https://example.com/p.png)") == "P(intro) UL[1:P([pic](https://example.com/p.png))]")
        #expect(outline("www.example.com/pic.png") == "P([www.example.com/pic.png](http://www.example.com/pic.png))")
    }

    @Test("Hidden spoilers become blocks, or inline links where blocks can't sit")
    func spoilers() {
        #expect(outline("Huge!>!he dies!< wow") == "P(Huge!) SPOILER(0) P(wow)")
        #expect(outline("https://example.com/a.png>!secret!< x") == "IMG(https://example.com/a.png) SPOILER(0) P(x)")
        #expect(outline("1. >!Tanjiro wins!<\n2. >!Zenitsu dies!<") == "OL[1:SPOILER(0); 2:SPOILER(1)]")
        #expect(outline("A|B\n-|-\n>!x!<|y") == "TABLE(A|B / [Spoiler](lurk-spoiler:0)|y)")
        #expect(outline("# Big >!x!< news") == "H1(Big [Spoiler](lurk-spoiler:0) news)")
        // CommentSpoilers doesn't see an indented code block; the spoiler still can't leak.
        #expect(outline("Code:\n\n    ls >!out.txt!<\n\nThe rest.") == "P(Code:) CODE(ls ) SPOILER(0) P(The rest.)")
        #expect(RedditMarkdown.spoilerID(in: URL(string: "lurk-spoiler:3")!) == 3)
    }

    @Test("A revealed spoiler stays inline: its \"#1\" or \"- \" can't open a block")
    func revealedSpoilers() {
        #expect(outline(">!#1 is Naruto!<", revealed: [0]) == "P(#1 is Naruto)")
        #expect(outline("> >!#1 is Naruto!<", revealed: [0]) == "Q[P(#1 is Naruto)]")
        #expect(outline("- >!#1 pick!<", revealed: [0]) == "UL[1:P(#1 pick)]")
        #expect(outline(">!_it_ y!< and >!www.example.com/a.png!<", revealed: [0, 1])
            == "P(_it_ y and [www.example.com/a.png](http://www.example.com/a.png))")
        #expect(outline("Look!>![here](https://example.com/page)!<", revealed: [0]) == "P(Look![here](https://example.com/page))")
    }

    @Test("A body that parses to nothing shows as written")
    func loneMarkers() {
        for marker in ["-", "#", "2."] {
            #expect(outline(marker) == "P(\(marker))")
        }
    }
}
