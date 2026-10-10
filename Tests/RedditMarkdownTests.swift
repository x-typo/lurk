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

// The text of every italic run, or of every run with `intent`, wherever it sits.
func emphasized(_ text: String, revealed: Set<Int> = [], intent: InlinePresentationIntent = .emphasized) -> [String] {
    func inline(_ text: AttributedString) -> [String] {
        text.runs.filter { $0.inlinePresentationIntent?.contains(intent) == true }.map { String(text[$0.range].characters) }
    }
    func visit(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text), .heading(_, let text): inline(text)
            case .quote(let blocks): visit(blocks)
            case .list(_, let items): items.flatMap { visit($0.blocks) }
            case .table(let table): ([table.header] + table.rows).flatMap { $0.flatMap(inline) }
            default: []
            }
        }
    }
    return visit(RedditMarkdown.blocks(from: text, revealedSpoilers: revealed))
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

    @Test("Images and GIFs lift out of prose, quotes, and headings, and stay links in lists and tables")
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

    @Test("Regressions from the sweep of the redesign against main stay fixed")
    func redesignSweep() {
        // A spoiler inside a link's label or a stray code span can still be revealed.
        #expect(outline("Read [the thread >!where he dies!<](https://redd.it/abc) after")
            == "P(Read [the thread](https://redd.it/abc)) SPOILER(0) P(after)")
        #expect(outline("[>!only!<](https://example.com/o)") == "SPOILER(0)")
        #expect(outline("A|B\n-|-\n[cell >!x!<](https://example.com/c)|y")
            == "TABLE(A|B / [cell ](https://example.com/c)[Spoiler](lurk-spoiler:0)|y)")
        #expect(outline("Press the ` key.\n\nThen type `god >!it makes you invincible!< ` and enter.")
            == "P(Press the ` key.) P(Then type `god`) SPOILER(0) P(and enter.)")
        // A bare URL ends at any space and leaves closing punctuation as prose.
        #expect(outline("He said “https://example.com/page” and 参考https://example.com/page。 ok")
            == "P(He said “[https://example.com/page](https://example.com/page)” and 参考[https://example.com/page](https://example.com/page)。 ok)")
        #expect(outline("画像 https://i.imgur.com/a.png\u{3000}かわいい") == "P(画像) IMG(https://i.imgur.com/a.png) P(かわいい)")
        #expect(outline("see https://example.com/page\u{00A0}and more")
            == "P(see [https://example.com/page](https://example.com/page)\u{00A0}and more)")
        #expect(outline("https://en.wikipedia.org/wiki/Foo_(bar)")
            == "P([https://en.wikipedia.org/wiki/Foo_(bar)](https://en.wikipedia.org/wiki/Foo_(bar)))")
        // A URL after an unclosed "[" still links, and a media one embeds.
        #expect(outline("sad :[ see https://example.com/page") == "P(sad :[ see [https://example.com/page](https://example.com/page))")
        #expect(outline("[Source: https://i.imgur.com/s.jpg]") == "P([Source:) IMG(https://i.imgur.com/s.jpg) P(])")
        // Linked images keep the image, and empty-text links show their address; code keeps its bytes.
        #expect(outline("Poster: [![](https://i.imgur.com/p.jpg)](https://example.com/show) nice")
            == "P(Poster:) IMG(https://i.imgur.com/p.jpg) P([https://example.com/show](https://example.com/show) nice)")
        #expect(outline("Look [](https://i.imgur.com/a.png) and [](https://example.com/page) more")
            == "P(Look) IMG(https://i.imgur.com/a.png) P(and [https://example.com/page](https://example.com/page) more)")
        #expect(outline("* ![](https://i.imgur.com/q.jpg)") == "UL[1:P([https://i.imgur.com/q.jpg](https://i.imgur.com/q.jpg))]")
        #expect(outline("```\n[![img](https://i.imgur.com/t.png)](https://example.com/full)\n[](x)\n<div>\n```")
            == "CODE([![img](https://i.imgur.com/t.png)](https://example.com/full)⏎[](x)⏎<div>)")
        // A revealed spoiler glued to a word or URL keeps its media.
        #expect(outline("Here>!https://i.redd.it/a.png!<", revealed: [0]) == "P(Here) IMG(https://i.redd.it/a.png)")
        #expect(outline(">!x!<https://i.redd.it/a.gif", revealed: [0]) == "P(x) GIF(https://i.redd.it/a.gif)")
        // Media in a heading lifts out of it.
        #expect(outline("## Look at this https://i.redd.it/a.gif") == "H2(Look at this) GIF(https://i.redd.it/a.gif)")
        // A tag-only line is text, so it can't swallow the quote or heading below it.
        #expect(outline("<rant>\n# Why I quit\n</rant>") == "P(<rant>) H1(Why I quit) P(</rant>)")
        #expect(outline("<rant>\nI hate this\n</rant>\n\n<edit>\nfixed typo\n</edit>")
            == "P(<rant>⏎I hate this⏎</rant>) P(<edit>⏎fixed typo⏎</edit>)")
        #expect(outline("<sarcasm>\n> Nobody could have predicted this").hasPrefix("P(<sarcasm>) Q["))
        // A body of only spaces, such as "&nbsp;", shows nothing.
        #expect(outline("&nbsp;").isEmpty)
        // ASCII punctuation hidden behind a non-ASCII mark or a no-break space leaves the URL too.
        #expect(outline("https://example.com/a.png.”") == "IMG(https://example.com/a.png) P(.”)")
        #expect(outline("see https://example.com/page.\u{00A0}and more")
            == "P(see [https://example.com/page](https://example.com/page).\u{00A0}and more)")
        // An explicit link that looks like an autolink keeps its own punctuation.
        #expect(outline("[https://example.com/search?q=why?](https://example.com/search?q=why?)")
            == "P([https://example.com/search?q=why?](https://example.com/search?q=why?))")
    }

    @Test("Inputs that broke the first, line-guessing approach still render as Reddit shows them")
    func firstApproachReviewInputs() {
        let gif = "GIF(https://media.giphy.com/media/abc/giphy.gif)"
        #expect(outline("before >!secret!< **important** and *italic*") == "P(before) SPOILER(0) P(**important** and _italic_)")
        #expect(outline("before >!secret!< *italic* after") == "P(before) SPOILER(0) P(_italic_ after)")
        // Fences end where CommonMark ends them, inside or after their quote or list, and code keeps its bytes.
        #expect(outline("  ~~~\n  code\n~~~\n![gif](giphy|abc)") == "CODE(code) \(gif)")
        #expect(outline("- > ~~~\n  > ![gif](giphy|abc)\n  > ~~~") == "UL[1:Q[CODE(![gif](giphy|abc))]]")
        #expect(outline("- ~~~\n\t![gif](giphy|abc)\n  ~~~") == "UL[1:CODE(  ![gif](giphy|abc))]")
        #expect(outline("```sh\n#!/bin/sh") == "CODE(#!/bin/sh)")
        #expect(outline("```\nA|B\n-|-\nx|[pic](https://example.com/p.png)\n```") == "CODE(A|B⏎-|-⏎x|[pic](https://example.com/p.png))")
        // Caret links keep their target with any scheme case, in angle brackets, and after quoted code.
        #expect(outline("Sources^[1](HTTPS://example.com/src)") == "P(Sources^[1](HTTPS://example.com/src))")
        #expect(outline("Sources^[1](<https://example.com/src>)") == "P(Sources^[1](https://example.com/src))")
        #expect(outline("> ~~~\n> code\n\nSources^[1](https://example.com/src)") == "Q[CODE(code)] P(Sources^[1](https://example.com/src))")
    }

    @Test("URLs keep balanced parentheses and brackets, and linked images keep titles and <…> addresses")
    func balancedURLs() {
        // A bare URL after an unclosed "[" goes through Lurk's own matcher rather than Foundation's.
        #expect(outline("[Source: https://example.com/a_(b).png]") == "P([Source:) IMG(https://example.com/a_(b).png) P(])")
        #expect(outline("[source: https://en.wikipedia.org/wiki/Mercury_(planet)]")
            == "P([source: [https://en.wikipedia.org/wiki/Mercury_(planet)](https://en.wikipedia.org/wiki/Mercury_(planet))])")
        #expect(outline("[see https://example.com/a_((b))]") == "P([see [https://example.com/a_((b))](https://example.com/a_((b)))])")
        #expect(outline("see https://example.com/?ids=[1,2] ok")
            == "P(see [https://example.com/?ids=[1,2]](https://example.com/?ids=%5B1,2%5D) ok)")
        #expect(outline("see http://[2001:db8::1] ok") == "P(see [http://[2001:db8::1]](http://[2001:db8::1]) ok)")
        // A ")" or "]" that closes nothing ends the URL.
        #expect(outline("[Source: (https://example.com/a.png),caption]") == "P([Source: () IMG(https://example.com/a.png) P(),caption])")
        #expect(outline("[![a](https://example.com/a_(b).png)](https://example.com/full)")
            == "IMG(https://example.com/a_(b).png) P([https://example.com/full](https://example.com/full))")
        #expect(outline("Poster: [![](https://i.imgur.com/p.jpg \"t\")](https://example.com/full 'u') nice")
            == "P(Poster:) IMG(https://i.imgur.com/p.jpg) P([https://example.com/full](https://example.com/full) nice)")
        #expect(outline("Poster: [![](<https://example.com/a b.png>)](<https://example.com/c)d>) nice")
            == "P(Poster:) IMG(https://example.com/a%20b.png) P([https://example.com/c)d](https://example.com/c)d) nice)")
        // A "<…>" or title that never closes, or an address that runs into the next "[![", doesn't hide the
        // linked image after it.
        for unclosed in ["`[![a](<`", "`[![a](x \"`", "`[![a](x (`"] {
            #expect(outline("\(unclosed) [![b](https://example.com/b.png)](https://example.com/page)")
                == "P(\(unclosed)) IMG(https://example.com/b.png) P([https://example.com/page](https://example.com/page))")
        }
        // A title that closes on the next linked image's own title doesn't hide that image either.
        #expect(outline("[![a](https://i.imgur.com/a.png \"t)](https://p.com/x) and [![b](https://i.imgur.com/b.png \"w\")](https://q.com/y) end")
            .hasSuffix("IMG(https://i.imgur.com/b.png) P([https://q.com/y](https://q.com/y) end)"))
        for prefix in ["`[![a](<`", "`[![a](i)](<x`"] {
            #expect(outline("\(prefix) [![b](https://example.com/b.png)](https://example.com/page) >")
                == "P(\(prefix)) IMG(https://example.com/b.png) P([https://example.com/page](https://example.com/page) >)")
        }
        for prefix in ["`[![a]((x)](y)`", "`[![a](i)](x(y)`"] {
            for opener in ["\"", "'", "("] {
                #expect(outline("\(prefix)[![b](https://example.com/b.png)](https://example.com/page) \(opener)")
                    == "P(\(prefix)) IMG(https://example.com/b.png) P([https://example.com/page](https://example.com/page) \(opener))")
            }
        }
    }

    @Test("A revealed spoiler's first line opens no block and its last line underlines nothing, as on Reddit")
    func revealedSpoilerLines() {
        #expect(outline(">!```!< and more\n\n# Heading", revealed: [0]) == "P(``` and more) H1(Heading)")
        #expect(outline("intro\n\n>![x]: https://example.com!<\n\nmore", revealed: [0])
            == "P(intro) P([x]: [https://example.com](https://example.com)) P(more)")
        #expect(outline(">!___!<\nafter", revealed: [0]) == "P(___⏎after)")
        #expect(outline("Intro\n\n>!    four spaces then text!<", revealed: [0]) == "P(Intro) P(four spaces then text)")
        #expect(outline(">!a\n---!<", revealed: [0]) == "P(a⏎---)")
        #expect(outline("x >!a\n___!<", revealed: [0]) == "P(x a⏎___)")
        #expect(outline("> >!a\n> ===!<", revealed: [0]) == "Q[P(a⏎===)]")
        #expect(outline(">!a\n!<- b", revealed: [0]) == "P(a⏎- b)")
        #expect(outline("> >!a\n> !<- b", revealed: [0]) == "Q[P(a⏎- b)]")
        #expect(outline("x >!a\n1.!< b", revealed: [0]) == "P(x a⏎1. b)")
        // Block syntax before the spoiler on its line still can't join with what it reveals.
        #expect(outline("#>!#1 pick!<", revealed: [0]) == "H1(#1 pick)")
        #expect(outline("->!    secret!<", revealed: [0]) == "P(-    secret)")
        // Lines between ">!" and "!<" are ordinary lines on Reddit, where these spoilers don't even form.
        #expect(outline(">!\n# secret!<") == "SPOILER(0)")
        #expect(outline(">!\n# secret!<", revealed: [0]) == "H1(secret)")
        #expect(outline("x >!a\n# b!<", revealed: [0]) == "P(x a) H1(b)")
        #expect(outline("> >!he dies\n> at the end!<", revealed: [0]) == "Q[P(he dies⏎at the end)]")
        // outline() can't tell italics from literal underscores, so these check the attribute itself.
        #expect(emphasized(">!_it_ y!<", revealed: [0]) == ["it"])
        #expect(emphasized("before >!secret!< *italic* after") == ["italic"])
        // A mark that guards a line never touches emphasis just before or after the spoiler.
        #expect(emphasized("**Source:**>![link](https://example.com)!<", revealed: [0], intent: .stronglyEmphasized) == ["Source:"])
        #expect(emphasized("*Note:*>![x](https://example.com)!<", revealed: [0]) == ["Note:"])
        #expect(emphasized("_see_>!    x!<", revealed: [0]) == ["see"])
        #expect(emphasized(">!The twist\n---!<_wow_", revealed: [0]) == ["wow"])
    }

    @Test("A long run of closing parentheses in a link is trimmed in linear time")
    func parenthesisRun() {
        let body = "[" + String(repeating: ")", count: 8000) + "”](https://example.com/x)"
        let elapsed = ContinuousClock().measure { _ = RedditMarkdown.blocks(from: body) }
        // Rescanning for every trimmed character took 0.62 s on a Mac; one pass takes milliseconds.
        #expect(elapsed < .seconds(0.2))
    }

    @Test("Linked images keep their image and link at any length, with brackets in the address")
    func linkedImages() {
        let alt = String(repeating: "a", count: 300)
        #expect(outline("[![\(alt)](https://i.imgur.com/t.png)](https://example.com/full)")
            == "IMG(https://i.imgur.com/t.png) P([https://example.com/full](https://example.com/full))")
        #expect(outline("Poster: [![](https://example.com/p.jpg?size[]=large)](https://example.com/show) nice")
            == "P(Poster:) IMG(https://example.com/p.jpg?size%5B%5D=large) P([https://example.com/show](https://example.com/show) nice)")
        let page = "https://example.com/" + String(repeating: "b", count: 1100)
        #expect(outline("x [![](https://i.imgur.com/t.png)](\(page)) y") == "P(x) IMG(https://i.imgur.com/t.png) P([\(page)](\(page)) y)")
        #expect(outline("[![a](https://i.imgur.com/t.png)](https://en.wikipedia.org/wiki/Foo_(bar))")
            == "IMG(https://i.imgur.com/t.png) P([https://en.wikipedia.org/wiki/Foo_(bar)](https://en.wikipedia.org/wiki/Foo_(bar)))")
        #expect(outline("```\n[![](https://e.com/p.jpg?s[]=1)](https://e.com/s)\n```") == "CODE([![](https://e.com/p.jpg?s[]=1)](https://e.com/s))")
        // Backslash escapes in the alt text or page address don't end the scan.
        #expect(outline("[![a \\[b](https://i.imgur.com/t.png)](https://example.com/p)")
            == "IMG(https://i.imgur.com/t.png) P([https://example.com/p](https://example.com/p))")
        #expect(outline("[![a](https://i.imgur.com/t.png)](https://example.com/p\\(x)")
            .hasPrefix("IMG(https://i.imgur.com/t.png) P("))
    }

    @Test("Long runs of linked images, giphy embeds, and fence-like runs parse in linear time")
    func patternRuns() {
        for (unit, count) in [
            ("[![", 8000), ("[![x](y", 8000), ("![gif](giphy|", 8000),
            ("![gif](giphy|a) ", 2000), ("[![a](https://i.imgur.com/t.png)](https://e.com/p) ", 1000), ("~~~ x ", 8000),
            ("https://(", 8000), ("[![a](((", 4000), ("[![a](<", 4000), ("[![a](x \"", 4000), ("[![a](x (", 4000),
        ] {
            let body = String(repeating: unit, count: count)
            let elapsed = ContinuousClock().measure { _ = RedditMarkdown.blocks(from: body) }
            // Rescanning took 0.9 to 4.6 s at these sizes; linear passes take well under a second in Debug.
            #expect(elapsed < .seconds(1), "\(unit) ×\(count) took \(elapsed)")
        }
        // Many nested addresses sharing one title that never closes.
        for opener in ["\"", "'", "("] {
            let body = String(repeating: "[![a](x", count: 8000) + " " + opener
            let elapsed = ContinuousClock().measure { _ = RedditMarkdown.blocks(from: body) }
            #expect(elapsed < .seconds(1), "unclosed \(opener) title took \(elapsed)")
        }
    }

    @Test("A long run of quote markers parses in linear time")
    func quoteMarkerRun() {
        let body = String(repeating: "> ", count: 60) + "x"
        let elapsed = ContinuousClock().measure { _ = RedditMarkdown.blocks(from: body) }
        // A backtracking pattern took 6.7 s at 26 markers; a linear scan takes milliseconds.
        #expect(elapsed < .seconds(1))
    }

    @Test("A body that parses to nothing shows as written")
    func loneMarkers() {
        for marker in ["-", "#", "2."] {
            #expect(outline(marker) == "P(\(marker))")
        }
    }
}
