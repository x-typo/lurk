import Foundation

// One block of a Reddit body. Headings, lists, tables, quotes, and code keep their structure; images, GIFs,
// and hidden spoilers are lifted out of the text around them.
indirect enum MarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case quote([MarkdownBlock])
    case list(ordered: Bool, items: [MarkdownListItem])
    case code(String)
    case table(MarkdownTable)
    case rule
    case image(URL)
    case gif(URL)
    // A GIF after the body's first, offered as a link instead of playing inline.
    case gifLink(URL)
    case spoiler(Int)
}

struct MarkdownListItem: Equatable {
    let ordinal: Int
    let blocks: [MarkdownBlock]
}

struct MarkdownTable: Equatable {
    let alignments: [PresentationIntent.TableColumn.Alignment]
    let header: [AttributedString]
    let rows: [[AttributedString]]
}

// Foundation's full Markdown parse decides a body's structure. Lurk adds only Reddit's own syntax, through
// private-use marks that Foundation reads as text and that are removed after parsing, so code keeps its
// bytes without Lurk having to find the code first.
enum RedditMarkdown {
    static let spoilerScheme = "lurk-spoiler"

    // Breaks the syntax it sits in: "^[", a revealed spoiler's leading "#" or "- ", "!" before "[".
    private static let mark: Character = "\u{E000}"
    // A giphy embed's "|", so a table doesn't split its cell there.
    private static let pipeMark: Character = "\u{E001}"
    // Follows the space added after a "#Title" heading's hashes, so code can drop that space again.
    private static let headingMark: Character = "\u{E003}"
    // Sits between a linked image, "[![alt](image)](page)", split into the image and a link to the page.
    private static let linkedImageMark: Character = "\u{E004}"

    // A top-level "#Title" line, which Reddit makes a heading and CommonMark doesn't. A line with a pipe
    // may be a table row, such as "#|Episode", so it's left alone.
    private static let compactHeadingPattern = try! NSRegularExpression(pattern: #"(?m)^( {0,3}#{1,6})(?=[^#\s])(?![^\n]*\|)"#)
    private static let giphyPattern = try! NSRegularExpression(pattern: #"!\[gif\]\(giphy\|[^)\s]*\)"#, options: .caseInsensitive)
    // Foundation flattens an image inside a link, losing the image.
    private static let linkedImagePattern = try! NSRegularExpression(pattern: #"\[(!\[[^\]\n]*\]\([^)\s]+\))\]\(([^)\s]+)\)"#)
    private static let linkedImageRestorePattern = try! NSRegularExpression(
        pattern: #"(!\[[^\]\n]*\]\([^)\s]+\))"# + String(linkedImageMark) + #"\["# + String(mark) + #"?\]\(([^)\s]+)\)"#
    )
    // A line starting with "<", which CommonMark may start an HTML block on. Reddit shows HTML as text, and
    // an HTML block would swallow the quote or heading below it.
    private static let htmlLinePattern = try! NSRegularExpression(pattern: #"(?m)^((?:[ \t]{0,3}>[ \t]?)*[ \t]{0,3})(?=<)"#)
    // A hidden spoiler's placeholder that ended up as text, inside a link's label or a code span.
    private static let nestedSpoilerPattern = try! NSRegularExpression(pattern: #"<?lurk-spoiler:(\d+)>?"#)
    private static let bareURLPattern = try! NSRegularExpression(pattern: #"https?://[^\s)"]+"#)
    private static let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]

    static func blocks(from text: String, revealedSpoilers: Set<Int> = []) -> [MarkdownBlock] {
        var hidden: Set<Int> = []
        let source = markedSource(text, revealedSpoilers: revealedSpoilers, hidden: &hidden)
        // Hidden spoilers stay hidden in every fallback.
        let visibleText = CommentSpoilers.selectionText(from: text, revealed: revealedSpoilers)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            return visibleText.isEmpty ? [] : [.paragraph(AttributedString(visibleText))]
        }
        let root = Node(intent: nil)
        var looseParagraph: (container: [PresentationIntent.IntentType], identity: Int)?
        var nextLooseIdentity = -1
        for run in parsed.runs {
            // Components list the innermost block first.
            var path = Array(run.presentationIntent?.components.reversed() ?? [])
            // Foundation leaves block HTML such as "<rant>" on its container, outside any paragraph;
            // a paragraph of its own keeps it in place.
            if path.isEmpty || run.inlinePresentationIntent?.contains(.blockHTML) == true {
                if looseParagraph?.container != path {
                    looseParagraph = (path, nextLooseIdentity)
                    nextLooseIdentity -= 1
                }
                path += PresentationIntent(.paragraph, identity: looseParagraph?.identity ?? 0).components
            } else {
                looseParagraph = nil
            }
            root.insert(inlineContent(parsed[run.range], intent: run.inlinePresentationIntent), along: path[...])
        }
        var blocks = lifted(root.children.compactMap(\.block), hidden: hidden, liftsMedia: true)
        limitInlineGIFs(&blocks)
        // A body that parses to nothing, such as a lone "-" or "#", shows as written; one that parses to
        // only spaces, such as "&nbsp;", shows nothing.
        if blocks.isEmpty, parsed.characters.isEmpty, !visibleText.isEmpty {
            return [.paragraph(AttributedString(visibleText))]
        }
        return blocks
    }

    // The spoiler a "lurk-spoiler:<id>" link stands for.
    static func spoilerID(in url: URL) -> Int? {
        guard url.scheme == spoilerScheme else { return nil }
        return Int(url.absoluteString.dropFirst(spoilerScheme.count + 1))
    }

    // MARK: Source

    private static func markedSource(_ text: String, revealedSpoilers: Set<Int>, hidden: inout Set<Int>) -> String {
        var source = ""
        for part in CommentSpoilers.parse(text) {
            var piece: String
            switch part {
            case .text(let text):
                piece = text
            case .spoiler(let id, let content) where revealedSpoilers.contains(id):
                // A spoiler is inline on Reddit, so its own "#1" or "- " can't open a block.
                let first = content.first { !$0.isWhitespace }
                let opensBlock = first.map { "#-+*>=".contains($0) || ($0.isASCII && $0.isNumber) } ?? false
                piece = opensBlock ? String(mark) + content : content
            case .spoiler(let id, _):
                // Only the id reaches the parser; an angle autolink can't be joined by a "!" or a URL before it.
                hidden.insert(id)
                piece = "<\(spoilerScheme):\(id)>"
            }
            // "!" before "[" would make an image, and a word glued to a revealed URL would stop it linking.
            if let last = source.last, let first = piece.first,
               (last == "!" && first == "[") || ((last.isLetter || last.isNumber) && (first.isLetter || first.isNumber)) {
                source.append(mark)
            }
            source += piece
        }
        source = linkedImagePattern.stringByReplacingMatches(
            in: source, range: NSRange(source.startIndex..., in: source),
            withTemplate: "$1" + String(linkedImageMark) + "[" + String(mark) + "]($2)"
        )
        // An empty-text link, "[](url)", gets text to show; its address replaces it after parsing.
        source = source.replacingOccurrences(of: #"(?<!!)\[\]\("#, with: "[" + String(mark) + "](", options: .regularExpression)
        // Foundation reads "^[text](url)" as its attribute syntax and drops the link; on Reddit it's a caret
        // and a link.
        source = source.replacingOccurrences(of: "^[", with: "^" + String(mark) + "[")
        for match in giphyPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            source.replaceSubrange(range, with: source[range].replacingOccurrences(of: "|", with: String(pipeMark)))
        }
        source = htmlLinePattern.stringByReplacingMatches(
            in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "$1" + String(mark)
        )
        return compactHeadingPattern.stringByReplacingMatches(
            in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "$1 " + String(headingMark)
        )
    }

    // Removes the marks, restoring the text as written.
    private static func unmarked(_ text: String) -> String {
        guard text.contains(where: { $0 == mark || $0 == pipeMark || $0 == headingMark || $0 == linkedImageMark }) else {
            return text
        }
        var text = text
        if text.contains(linkedImageMark) {
            text = linkedImageRestorePattern.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$1]($2)"
            )
        }
        return text
            .replacingOccurrences(of: String(linkedImageMark), with: "")
            .replacingOccurrences(of: " " + String(headingMark), with: "")
            .replacingOccurrences(of: String(headingMark), with: "")
            .replacingOccurrences(of: String(mark), with: "")
            .replacingOccurrences(of: String(pipeMark), with: "|")
    }

    private static func unmarked(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains("%EE%80%8") else { return url }
        let restored = text
            .replacingOccurrences(of: "%20%EE%80%83", with: "")
            .replacingOccurrences(of: "%EE%80%83", with: "")
            .replacingOccurrences(of: "%EE%80%80", with: "")
            .replacingOccurrences(of: "%EE%80%84", with: "")
            .replacingOccurrences(of: "%EE%80%81", with: "%7C")
        return URL(string: restored) ?? url
    }

    private static func unmarked(_ text: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in text.runs {
            var attributes = run.attributes
            if let link = run.link { attributes.link = unmarked(link) }
            if let imageURL = run.imageURL { attributes.imageURL = unmarked(imageURL) }
            result += AttributedString(unmarked(String(text[run.range].characters)), attributes: attributes)
        }
        return result
    }

    private static func inlineContent(_ slice: AttributedSubstring, intent: InlinePresentationIntent?) -> AttributedString {
        // Lurk shows a body's single newlines as line breaks, as before block parsing.
        if intent?.contains(.softBreak) == true {
            return AttributedString("\n")
        }
        // Full syntax leaves block HTML, such as a "<sarcasm>" line and the lines after it, as raw text; its
        // Markdown still renders inline, as before block parsing.
        var content: AttributedString
        if intent?.contains(.blockHTML) == true {
            var html = String(slice.characters)
            if html.hasSuffix("\n") { html.removeLast() }
            content = (try? AttributedString(markdown: html, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(html)
        } else {
            content = AttributedString(slice)
            content.presentationIntent = nil
        }
        // "[](url)", and an empty-alt image that stays a link, show their address.
        var addressed = AttributedString()
        for run in content.runs {
            let runText = String(content[run.range].characters)
            if runText == String(mark) || runText == "\u{FFFC}", let target = run.link ?? run.imageURL {
                addressed += AttributedString(unmarked(target).absoluteString, attributes: run.attributes)
            } else {
                addressed += AttributedString(content[run.range])
            }
        }
        content = addressed
        // "![clip](https://…)" keeps its target as a link; a media one is lifted out later.
        for (imageURL, range) in content.runs[\.imageURL].reversed() {
            guard let imageURL, content[range].link == nil, isWebURL(imageURL) else { continue }
            content[range].link = imageURL
        }
        return normalizedLinks(unmarked(content))
    }

    // An autolink ends at any space, including a no-break one, and leaves closing punctuation such as "”" or
    // "。" as prose. A URL Foundation didn't link, such as one after an unclosed "[", is linked as before.
    private static func normalizedLinks(_ text: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in text.runs {
            let runText = String(text[run.range].characters)
            if run.inlinePresentationIntent?.contains(.code) == true {
                result += AttributedString(text[run.range])
            } else if let link = run.link {
                let cut = runText.firstIndex(where: \.isWhitespace) ?? runText.endIndex
                let (address, punctuation) = splitTrailingPunctuation(from: String(runText[..<cut]))
                guard isWebURL(link), URL(string: runText) == link, address != runText, let url = URL(string: address) else {
                    result += AttributedString(text[run.range])
                    continue
                }
                var linked = AttributedString(address, attributes: run.attributes)
                linked.link = url
                var rest = AttributedString(punctuation + runText[cut...], attributes: run.attributes)
                rest.link = nil
                result += linked + rest
            } else {
                result += linkedURLs(in: runText, attributes: run.attributes)
            }
        }
        return result
    }

    private static func linkedURLs(in text: String, attributes: AttributeContainer) -> AttributedString {
        var plain = attributes
        plain.link = nil
        let nsText = text as NSString
        var result = AttributedString()
        var last = 0
        for match in bareURLPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let (address, _) = splitTrailingPunctuation(from: nsText.substring(with: match.range))
            guard let url = URL(string: address) else { continue }
            result += AttributedString(nsText.substring(with: NSRange(location: last, length: match.range.location - last)), attributes: plain)
            var linked = AttributedString(address, attributes: plain)
            linked.link = url
            result += linked
            last = match.range.location + (address as NSString).length
        }
        result += AttributedString(nsText.substring(from: last), attributes: plain)
        return result
    }

    // MARK: Lifting

    private static func lifted(_ blocks: [MarkdownBlock], hidden: Set<Int>, liftsMedia: Bool) -> [MarkdownBlock] {
        blocks.flatMap { block -> [MarkdownBlock] in
            switch block {
            case .paragraph(let text):
                return lifted(text, hidden: hidden, liftsMedia: liftsMedia, spoilersInline: false) { .paragraph($0) }
            case .heading(let level, let text):
                return lifted(text, hidden: hidden, liftsMedia: liftsMedia, spoilersInline: true) { .heading(level: level, $0) }
            case .quote(let blocks):
                return [.quote(lifted(blocks, hidden: hidden, liftsMedia: liftsMedia))]
            case .list(let ordered, let items):
                // Media in a list item stays a link, so the item's marker keeps its text beside it.
                return [.list(ordered: ordered, items: items.map {
                    MarkdownListItem(ordinal: $0.ordinal, blocks: lifted($0.blocks, hidden: hidden, liftsMedia: false))
                })]
            case .table(let table):
                return [.table(MarkdownTable(
                    alignments: table.alignments,
                    header: table.header.map { inline($0, hidden: hidden) },
                    rows: table.rows.map { $0.map { inline($0, hidden: hidden) } }
                ))]
            case .code(let code):
                return liftedSpoilers(fromCode: code, hidden: hidden)
            default:
                return [block]
            }
        }
    }

    // Splits a paragraph or heading around its hidden spoilers and, where blocks can sit, its images and GIFs.
    // In a heading a hidden spoiler stays an inline "Spoiler" link.
    private static func lifted(
        _ text: AttributedString, hidden: Set<Int>, liftsMedia: Bool, spoilersInline: Bool,
        wrap: (AttributedString) -> MarkdownBlock
    ) -> [MarkdownBlock] {
        let text = separatingNestedSpoilers(text, hidden: hidden)
        var blocks: [MarkdownBlock] = []
        var pending = AttributedString()
        func flush() {
            let piece = trimmed(pending)
            if !piece.characters.isEmpty { blocks.append(wrap(piece)) }
            pending = AttributedString()
        }
        for run in text.runs {
            let piece = AttributedString(text[run.range])
            if let id = hiddenSpoiler(run.link, hidden: hidden) {
                if spoilersInline {
                    pending += linked(AttributedString("Spoiler"), to: run.link)
                } else {
                    flush()
                    blocks.append(.spoiler(id))
                }
            } else if run.inlinePresentationIntent?.contains(.code) == true {
                pending += piece
            } else if let giphy = giphyURL(run.imageURL) {
                if liftsMedia {
                    flush()
                    blocks.append(.gif(giphy))
                } else {
                    pending += linked(piece, to: giphy)
                }
            } else if liftsMedia, let found = media(in: run, text: String(text[run.range].characters)) {
                flush()
                blocks.append(found.block)
                pending += AttributedString(found.trailing)
            } else {
                pending += piece
            }
        }
        flush()
        return blocks
    }

    // Headings and table cells can't hold blocks: a hidden spoiler stays an inline "Spoiler" link that
    // reveals it, and a giphy embed links to its GIF.
    private static func inline(_ text: AttributedString, hidden: Set<Int>) -> AttributedString {
        let text = separatingNestedSpoilers(text, hidden: hidden)
        var result = AttributedString()
        for run in text.runs {
            let piece = AttributedString(text[run.range])
            if hiddenSpoiler(run.link, hidden: hidden) != nil {
                result += linked(AttributedString("Spoiler"), to: run.link)
            } else if let giphy = giphyURL(run.imageURL) {
                result += linked(piece, to: giphy)
            } else {
                result += piece
            }
        }
        return result
    }

    // A hidden spoiler inside a link's label can't be a link of its own, so Foundation leaves its placeholder
    // as text in the outer link; one in a code span CommentSpoilers paired differently stays raw. Either
    // becomes its own spoiler link again, and the text around it keeps its link.
    private static func separatingNestedSpoilers(_ text: AttributedString, hidden: Set<Int>) -> AttributedString {
        guard !hidden.isEmpty, String(text.characters).contains("\(spoilerScheme):") else { return text }
        var result = AttributedString()
        for run in text.runs {
            let runText = String(text[run.range].characters)
            let nsText = runText as NSString
            var pieces = AttributedString()
            var last = 0
            if hiddenSpoiler(run.link, hidden: hidden) == nil {
                for match in nestedSpoilerPattern.matches(in: runText, range: NSRange(location: 0, length: nsText.length)) {
                    guard let id = Int(nsText.substring(with: match.range(at: 1))), hidden.contains(id) else { continue }
                    pieces += AttributedString(
                        nsText.substring(with: NSRange(location: last, length: match.range.location - last)), attributes: run.attributes
                    )
                    var spoiler = AttributedString("\(spoilerScheme):\(id)", attributes: run.attributes)
                    spoiler.link = URL(string: "\(spoilerScheme):\(id)")
                    pieces += spoiler
                    last = match.range.location + match.range.length
                }
            }
            if last == 0 {
                result += AttributedString(text[run.range])
            } else {
                result += pieces + AttributedString(nsText.substring(from: last), attributes: run.attributes)
            }
        }
        return result
    }

    // A spoiler that CommentSpoilers found inside code it doesn't recognize, such as an indented block.
    private static func liftedSpoilers(fromCode code: String, hidden: Set<Int>) -> [MarkdownBlock] {
        let opener = "<\(spoilerScheme):"
        guard !hidden.isEmpty, code.contains(opener) else { return [.code(code)] }
        var blocks: [MarkdownBlock] = []
        func appendCode(_ text: Substring) {
            let code = text.trimmingCharacters(in: .newlines)
            if !code.trimmingCharacters(in: .whitespaces).isEmpty { blocks.append(.code(code)) }
        }
        var rest = code[...]
        while let open = rest.range(of: opener),
              let close = rest[open.upperBound...].firstIndex(of: ">"),
              let id = Int(rest[open.upperBound..<close]), hidden.contains(id) {
            appendCode(rest[..<open.lowerBound])
            blocks.append(.spoiler(id))
            rest = rest[rest.index(after: close)...]
        }
        appendCode(rest)
        return blocks
    }

    // An image or GIF a run stands for: image syntax, a Markdown link, or a bare URL, whose trailing
    // punctuation such as "…" stays prose.
    private static func media(in run: AttributedString.Runs.Run, text: String) -> (block: MarkdownBlock, trailing: String)? {
        if let imageURL = run.imageURL, let block = mediaBlock(imageURL) {
            return (block, "")
        }
        guard let link = run.link, isWebURL(link), !text.lowercased().hasPrefix("www.") else { return nil }
        if URL(string: text) == link {
            let (address, trailing) = splitTrailingPunctuation(from: text)
            guard let url = URL(string: address), let block = mediaBlock(url) else { return nil }
            return (block, trailing)
        }
        return mediaBlock(link).map { ($0, "") }
    }

    private static func mediaBlock(_ url: URL) -> MarkdownBlock? {
        guard isWebURL(url), imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url.pathExtension.lowercased() == "gif" ? .gif(url) : .image(url)
    }

    private static func hiddenSpoiler(_ link: URL?, hidden: Set<Int>) -> Int? {
        guard let link, let id = spoilerID(in: link), hidden.contains(id) else { return nil }
        return id
    }

    // "![gif](giphy|ID)" or "![gif](giphy|ID|variant)", Reddit's giphy embed.
    private static func giphyURL(_ imageURL: URL?) -> URL? {
        guard let decoded = imageURL?.absoluteString.removingPercentEncoding,
              decoded.lowercased().hasPrefix("giphy|") else { return nil }
        let id = decoded.dropFirst("giphy|".count).split(separator: "|").first ?? ""
        return URL(string: "https://media.giphy.com/media/\(id)/giphy.gif")
    }

    private static func linked(_ text: AttributedString, to url: URL?) -> AttributedString {
        var text = text
        text.link = url
        text.imageURL = nil
        return text
    }

    private static func trimmed(_ text: AttributedString) -> AttributedString {
        guard let first = text.characters.firstIndex(where: { !$0.isWhitespace }),
              let last = text.characters.lastIndex(where: { !$0.isWhitespace }) else { return AttributedString() }
        return AttributedString(text[first...last])
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    private static func splitTrailingPunctuation(from token: String) -> (String, String) {
        var urlString = token
        var trailingText = ""
        let punctuation = CharacterSet.punctuationCharacters
        let preservedURLCharacters = CharacterSet(charactersIn: "/-_~%+=&#@$*")
        while let scalar = urlString.unicodeScalars.last,
              punctuation.contains(scalar),
              !preservedURLCharacters.contains(scalar),
              scalar != ")" || urlString.filter({ $0 == ")" }).count > urlString.filter({ $0 == "(" }).count {
            let character = urlString.removeLast()
            trailingText.insert(character, at: trailingText.startIndex)
        }
        return (urlString, trailingText)
    }

    // The first GIF in reading order plays inline; later ones become links.
    private static func limitInlineGIFs(_ blocks: inout [MarkdownBlock]) {
        var seenGIF = false
        func visit(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
            blocks.map { block in
                switch block {
                case .gif(let url):
                    if seenGIF { return .gifLink(url) }
                    seenGIF = true
                    return block
                case .quote(let inner):
                    return .quote(visit(inner))
                case .list(let ordered, let items):
                    return .list(ordered: ordered, items: items.map { MarkdownListItem(ordinal: $0.ordinal, blocks: visit($0.blocks)) })
                default:
                    return block
                }
            }
        }
        blocks = visit(blocks)
    }

    // MARK: Tree

    private final class Node {
        let intent: PresentationIntent.IntentType?
        var children: [Node] = []
        var content = AttributedString()

        init(intent: PresentationIntent.IntentType?) {
            self.intent = intent
        }

        func insert(_ text: AttributedString, along path: ArraySlice<PresentationIntent.IntentType>) {
            guard let next = path.first else {
                content.append(text)
                return
            }
            let child: Node
            if let last = children.last, last.intent?.identity == next.identity {
                child = last
            } else {
                child = Node(intent: next)
                children.append(child)
            }
            child.insert(text, along: path.dropFirst())
        }

        var block: MarkdownBlock? {
            guard let kind = intent?.kind else { return nil }
            switch kind {
            case .paragraph:
                return .paragraph(content)
            case .header(let level):
                return .heading(level: level, content)
            case .blockQuote:
                return .quote(children.compactMap(\.block))
            case .orderedList, .unorderedList:
                let items = children.compactMap { child -> MarkdownListItem? in
                    guard case .listItem(let ordinal) = child.intent?.kind else { return nil }
                    return MarkdownListItem(ordinal: ordinal, blocks: child.children.compactMap(\.block))
                }
                return .list(ordered: kind == .orderedList, items: items)
            case .codeBlock:
                var code = String(content.characters)
                if code.hasSuffix("\n") { code.removeLast() }
                return .code(code)
            case .thematicBreak:
                return .rule
            case .table(let columns):
                var header: [AttributedString] = []
                var rows: [[AttributedString]] = []
                for row in children {
                    var cells = Array(repeating: AttributedString(), count: columns.count)
                    for cell in row.children {
                        guard case .tableCell(let column) = cell.intent?.kind, cells.indices.contains(column) else { continue }
                        cells[column] = cell.content
                    }
                    if case .tableHeaderRow = row.intent?.kind {
                        header = cells
                    } else {
                        rows.append(cells)
                    }
                }
                return .table(MarkdownTable(alignments: columns.map(\.alignment), header: header, rows: rows))
            case .listItem, .tableHeaderRow, .tableRow, .tableCell:
                return nil
            @unknown default:
                return content.characters.isEmpty ? nil : .paragraph(content)
            }
        }
    }
}
