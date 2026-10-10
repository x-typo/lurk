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
// bytes without Lurk having to find the code first. A body's own copies of those characters, such as the
// private-use glyphs some games' players paste, are escaped first and restored after; one written as an
// HTML character reference, such as "&#xE000;", isn't.
enum RedditMarkdown {
    static let spoilerScheme = "lurk-spoiler"

    // Breaks the syntax it sits in: "^[", a revealed spoiler's leading "#" or "- ", "!" before "[".
    private static let mark: Character = "\u{E000}"
    // A giphy embed's "|", so a table doesn't split its cell there.
    private static let pipeMark: Character = "\u{E001}"
    // Follows the space added after a "#Title" heading's hashes, so code can drop that space again.
    private static let headingMark: Character = "\u{E003}"
    // A linked image, "[![alt](image)](page)", is split into the image and a link to the page: this mark
    // stands for its "[", and `linkedImageMark` sits between the two.
    private static let linkedImageStartMark: Character = "\u{E005}"
    private static let linkedImageMark: Character = "\u{E004}"
    // Stands for a revealed spoiler's ">!" and "!<", and goes after parsing. Unlike the marks above, it's
    // punctuation (U+2E3F CAPITULUM), as those delimiters are on Reddit, so emphasis beside it closes and
    // opens as it does there.
    private static let delimiterMark: Character = "\u{2E3F}"
    // Every character above, as the body itself holds it, becomes `escapeMark` and the stand-in at the same
    // index from U+F700, so none can be taken for a mark; `unmarked` restores them.
    private static let escapeMark: Unicode.Scalar = "\u{E00F}"
    private static let reservedScalars: [Unicode.Scalar] = ["\u{E000}", "\u{E001}", "\u{E003}", "\u{E004}", "\u{E005}", "\u{2E3F}", "\u{E00F}"]
    private static let standInBase: UInt32 = 0xF700

    // A top-level "#Title" line, which Reddit makes a heading and CommonMark doesn't. A line with a pipe
    // may be a table row, such as "#|Episode", so it's left alone.
    private static let compactHeadingPattern = try! NSRegularExpression(pattern: #"(?m)^( {0,3}#{1,6})(?=[^#\s])(?![^\n]*\|)"#)
    // Capped, so a long line of "![gif](giphy|" without a closing ")" doesn't rescan to its end each time.
    private static let giphyPattern = try! NSRegularExpression(pattern: #"!\[gif\]\(giphy\|[^)\s]{0,100}\)"#, options: .caseInsensitive)
    // A hidden spoiler's placeholder that ended up as text, inside a link's label or a code span.
    private static let nestedSpoilerPattern = try! NSRegularExpression(pattern: #"<?lurk-spoiler:(\d+)>?"#)
    private static let bareURLStartPattern = try! NSRegularExpression(pattern: #"https?://"#)
    private static let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]

    static func blocks(from text: String, revealedSpoilers: Set<Int> = []) -> [MarkdownBlock] {
        var hidden: Set<Int> = []
        let source = markedSource(text, revealedSpoilers: revealedSpoilers, hidden: &hidden)
        // Hidden spoilers stay hidden in every fallback.
        func visibleText() -> String {
            CommentSpoilers.selectionText(from: text, revealed: revealedSpoilers).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            let visible = visibleText()
            return visible.isEmpty ? [] : [.paragraph(AttributedString(visible))]
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
        limitTableCells(&blocks)
        // A body that parses to nothing, such as a lone "-" or "#", shows as written; one that parses to
        // only spaces, such as "&nbsp;", shows nothing.
        if blocks.isEmpty, parsed.characters.isEmpty {
            let visible = visibleText()
            return visible.isEmpty ? [] : [.paragraph(AttributedString(visible))]
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
        let text = escapedReserved(text)
        for part in CommentSpoilers.parse(text) {
            switch part {
            case .text(let text):
                source += text
            case .spoiler(let id, let content) where revealedSpoilers.contains(id):
                // On Reddit, ">!" and "!<" stay in the source around the spoiler, so its first line can't
                // open or extend a block, its last line can't underline one, and the line after it can't
                // start one; lines between are ordinary lines. `delimiterMark` stands in for both, except
                // before a letter that starts a line or follows a space: nothing can open there, and a URL
                // still links, as Foundation's autolinks need a space before them.
                let opensWithWord = content.first?.isLetter == true && (source.last?.isWhitespace ?? true)
                source += (opensWithWord ? "" : String(delimiterMark)) + content + String(delimiterMark)
            case .spoiler(let id, _):
                // Only the id reaches the parser; an angle autolink can't be joined by a "!" or a URL before it.
                hidden.insert(id)
                source += "<\(spoilerScheme):\(id)>"
            }
        }
        source = splittingLinkedImages(source)
        // An empty-text link, "[](url)", gets text to show; its address replaces it after parsing.
        source = source.replacingOccurrences(of: #"(?<!!)\[\]\("#, with: "[" + String(mark) + "](", options: .regularExpression)
        // Foundation reads "^[text](url)" as its attribute syntax and drops the link; on Reddit it's a caret
        // and a link.
        source = source.replacingOccurrences(of: "^[", with: "^" + String(mark) + "[")
        // One forward pass, so many embeds don't each shift the rest of the body.
        var piped = ""
        var copied = source.startIndex
        for match in giphyPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source) else { continue }
            piped += source[copied..<range.lowerBound]
            piped += source[range].replacingOccurrences(of: "|", with: String(pipeMark))
            copied = range.upperBound
        }
        source = piped + source[copied...]
        source = markingHTMLLines(source)
        return compactHeadingPattern.stringByReplacingMatches(
            in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "$1 " + String(headingMark)
        )
    }

    // Rewrites "[![alt](image)](page)" as "<start>![alt](image)<split>[<mark>](page)", the image and a link
    // to the page, since Foundation flattens an image inside a link. In code, <start> becomes "[" again and
    // "<split>[<mark>" goes. One forward scan: a failed match resumes where it failed, so each character is
    // read at most twice, whatever the lengths.
    private static func splittingLinkedImages(_ source: String) -> String {
        guard source.contains("[![") else { return source }
        let characters = Array(source)
        // A backslash escape, such as "\[" or "\(", reads as one ordinary character.
        func step(_ cursor: Int) -> Int {
            let isEscape = characters[cursor] == "\\" && cursor + 1 < characters.count
                && ##"!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"##.contains(characters[cursor + 1])
            return cursor + (isEscape ? 2 : 1)
        }
        func startsLinkedImage(at cursor: Int) -> Bool {
            cursor + 2 < characters.count && characters[cursor] == "[" && characters[cursor + 1] == "!" && characters[cursor + 2] == "["
        }
        // Where a link's address and optional title end: `.end` at the ")" that closes them, or where the
        // scan gave up. An address is "<…>", which may hold spaces and parentheses, or runs to whitespace past
        // any balanced "(…)", stopping at the next "[![" so a failed scan never hides the next linked image.
        // A "<…>" or title that never closes is `.unclosed`: the scan resumes at its opener, so a linked
        // image inside it still counts. Each of those scans stops at its own opener too, as CommonMark
        // requires, so scans of one kind never overlap and the pass stays linear.
        enum Destination {
            case end(Int)
            case unclosed(resume: Int)
        }
        func destinationEnd(from start: Int) -> Destination {
            var cursor = start
            if cursor < characters.count, characters[cursor] == "<" {
                cursor += 1
                while cursor < characters.count, !"<>\n".contains(characters[cursor]), !startsLinkedImage(at: cursor) { cursor = step(cursor) }
                guard cursor < characters.count, characters[cursor] == ">" else { return .unclosed(resume: start) }
                cursor += 1
            } else {
                var depth = 0
                while cursor < characters.count, !characters[cursor].isWhitespace, !startsLinkedImage(at: cursor) {
                    if characters[cursor] == "(" {
                        depth += 1
                    } else if characters[cursor] == ")" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    cursor = step(cursor)
                }
            }
            let titleStart = skipSpaces(from: cursor)
            let closers: [Character: Character] = ["\"": "\"", "'": "'", "(": ")"]
            guard titleStart > cursor, titleStart < characters.count, let close = closers[characters[titleStart]] else {
                return .end(titleStart)
            }
            let opener = characters[titleStart]
            cursor = titleStart + 1
            while cursor < characters.count, characters[cursor] != close, characters[cursor] != opener, characters[cursor] != "\n",
                  !startsLinkedImage(at: cursor) {
                cursor = step(cursor)
            }
            guard cursor < characters.count, characters[cursor] == close else { return .unclosed(resume: titleStart) }
            return .end(skipSpaces(from: cursor + 1))
        }
        func skipSpaces(from start: Int) -> Int {
            var cursor = start
            while cursor < characters.count, characters[cursor] == " " || characters[cursor] == "\t" { cursor += 1 }
            return cursor
        }
        var result = ""
        var copied = 0
        var index = 0
        while index + 2 < characters.count {
            guard startsLinkedImage(at: index) else {
                index += 1
                continue
            }
            var cursor = index + 3
            while cursor < characters.count, !"[]\n".contains(characters[cursor]) { cursor = step(cursor) }
            guard cursor + 1 < characters.count, characters[cursor] == "]", characters[cursor + 1] == "(" else {
                index = max(cursor, index + 1)
                continue
            }
            cursor += 2
            let imageStart = cursor
            switch destinationEnd(from: cursor) {
            case .end(let end): cursor = end
            case .unclosed(let resume):
                index = max(resume, index + 1)
                continue
            }
            guard cursor > imageStart, cursor + 2 < characters.count,
                  characters[cursor] == ")", characters[cursor + 1] == "]", characters[cursor + 2] == "(" else {
                index = max(cursor, index + 1)
                continue
            }
            let imageEnd = cursor + 1
            cursor += 3
            let pageStart = cursor
            switch destinationEnd(from: cursor) {
            case .end(let end): cursor = end
            case .unclosed(let resume):
                index = max(resume, index + 1)
                continue
            }
            guard cursor > pageStart, cursor < characters.count, characters[cursor] == ")" else {
                index = max(cursor, index + 1)
                continue
            }
            result += String(characters[copied..<index])
            result.append(delimiterMark)
            result.append(linkedImageStartMark)
            result += String(characters[(index + 1)..<imageEnd])
            result += String(linkedImageMark) + "[" + String(mark) + "]("
            result += String(characters[pageStart..<cursor]) + ")"
            index = cursor + 1
            copied = index
        }
        return result + String(characters[copied...])
    }

    // A line starting with "<", after any quote markers, gets a mark: CommonMark could open an HTML block
    // there, which would swallow the quote or heading below it, and Reddit shows HTML as text. A scan, not a
    // regex: a repeated optional prefix backtracks exponentially on a long run of "> ".
    private static func markingHTMLLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var index = line.startIndex
            func skipIndent() {
                var count = 0
                while index < line.endIndex, count < 3, line[index] == " " || line[index] == "\t" {
                    index = line.index(after: index)
                    count += 1
                }
            }
            skipIndent()
            while index < line.endIndex, line[index] == ">" {
                index = line.index(after: index)
                if index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) }
                skipIndent()
            }
            guard index < line.endIndex, line[index] == "<" else { return String(line) }
            return String(line[..<index]) + String(mark) + line[index...]
        }
        .joined(separator: "\n")
    }

    // Removes the marks, restoring the text as written.
    private static func unmarked(_ text: String) -> String {
        let marks = [mark, pipeMark, headingMark, linkedImageMark, linkedImageStartMark, delimiterMark, Character(escapeMark)]
        guard text.contains(where: marks.contains) || text.contains("%EE%80%8F%EF%9C%8") else {
            return text
        }
        // Code holds a split linked image whole; parsed text has its pieces in separate runs.
        let split = String(linkedImageMark) + "[" + String(mark)
        let isWholeLinkedImage = text.contains(split)
        let unmarked = text
            .replacingOccurrences(of: split, with: "")
            .replacingOccurrences(of: String(linkedImageStartMark), with: isWholeLinkedImage ? "[" : "")
            .replacingOccurrences(of: String(linkedImageMark), with: "")
            .replacingOccurrences(of: " " + String(headingMark), with: "")
            .replacingOccurrences(of: String(headingMark), with: "")
            .replacingOccurrences(of: String(mark), with: "")
            .replacingOccurrences(of: String(delimiterMark), with: "")
            .replacingOccurrences(of: String(pipeMark), with: "|")
        return restoringEncodedReserved(restoringReserved(unmarked))
    }

    private static func percentEncoded(_ scalar: Unicode.Scalar) -> String {
        String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
    }

    // A body's own percent-encoded copies, as in a link, in Foundation's uppercase form; the URL clean-up
    // reads only that form.
    private static let encodedReservedPattern = try! NSRegularExpression(pattern: "%EE%80%8[01345F]|%E2%B8%BF")

    private static func escapedReserved(_ text: String) -> String {
        escapedEncodedReserved(escapedReservedScalars(text))
    }

    private static func escapedEncodedReserved(_ text: String) -> String {
        let nsText = text as NSString
        var escaped = ""
        var copied = 0
        for match in encodedReservedPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let encoded = nsText.substring(with: match.range)
            guard let index = reservedScalars.firstIndex(where: { percentEncoded($0) == encoded }),
                  let standIn = Unicode.Scalar(standInBase + UInt32(index)) else { continue }
            escaped += nsText.substring(with: NSRange(location: copied, length: match.range.location - copied))
            escaped += percentEncoded(escapeMark) + percentEncoded(standIn)
            copied = NSMaxRange(match.range)
        }
        return copied == 0 ? text : escaped + nsText.substring(from: copied)
    }

    private static func escapedReservedScalars(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: reservedScalars.contains) else { return text }
        var escaped = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if let index = reservedScalars.firstIndex(of: scalar), let standIn = Unicode.Scalar(standInBase + UInt32(index)) {
                escaped.append(escapeMark)
                escaped.append(standIn)
            } else {
                escaped.append(scalar)
            }
        }
        return String(escaped)
    }

    private static func restoringReserved(_ text: String) -> String {
        guard text.unicodeScalars.contains(escapeMark) else { return text }
        var restored = String.UnicodeScalarView()
        var escaping = false
        for scalar in text.unicodeScalars {
            if escaping {
                escaping = false
                let index = Int(scalar.value) - Int(standInBase)
                if reservedScalars.indices.contains(index) {
                    restored.append(reservedScalars[index])
                    continue
                }
                restored.append(escapeMark)
            }
            if scalar == escapeMark {
                escaping = true
            } else {
                restored.append(scalar)
            }
        }
        if escaping { restored.append(escapeMark) }
        return String(restored)
    }

    // The same pairs, percent-encoded, in one pass.
    private static let encodedEscapePattern = try! NSRegularExpression(pattern: "%EE%80%8F%EF%9C%8([0-9A-F])")

    private static func restoringEncodedReserved(_ text: String) -> String {
        let nsText = text as NSString
        var restored = ""
        var copied = 0
        for match in encodedEscapePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let index = Int(nsText.substring(with: match.range(at: 1)), radix: 16), reservedScalars.indices.contains(index) else {
                continue
            }
            restored += nsText.substring(with: NSRange(location: copied, length: match.range.location - copied))
            restored += percentEncoded(reservedScalars[index])
            copied = NSMaxRange(match.range)
        }
        return restored + nsText.substring(from: copied)
    }

    private static func unmarked(_ url: URL) -> URL {
        let stripped = withoutInjectedMarks(url)
        return URL(string: restoringEncodedReserved(stripped.absoluteString)) ?? stripped
    }

    private static func withoutInjectedMarks(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains("%EE%80%8") else { return url }
        let restored = text
            .replacingOccurrences(of: "%20%EE%80%83", with: "")
            .replacingOccurrences(of: "%EE%80%83", with: "")
            .replacingOccurrences(of: "%EE%80%80", with: "")
            .replacingOccurrences(of: "%EE%80%84", with: "")
            .replacingOccurrences(of: "%EE%80%85", with: "")
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
                // Restored with the rest of the text below, so only the injected marks go here.
                addressed += AttributedString(withoutInjectedMarks(target).absoluteString, attributes: run.attributes)
            } else {
                addressed += AttributedString(content[run.range])
            }
        }
        content = addressed
        // Foundation's autolinks run on through a revealed spoiler's closing mark; they end there, as at "!<".
        var ended = AttributedString()
        for run in content.runs {
            let runText = String(content[run.range].characters)
            let lowered = runText.lowercased()
            if let link = run.link, let cut = runText.firstIndex(of: delimiterMark), cut != runText.startIndex,
               ["http://", "https://", "www."].contains(where: lowered.hasPrefix),
               URL(string: lowered.hasPrefix("www.") ? "http://" + runText : runText) == link {
                // The mark hid any trailing punctuation from Foundation, so trim it here as Foundation would.
                let (address, trailing) = splitTrailingPunctuation(from: String(runText[..<cut]), includingEmphasis: true)
                var linked = AttributedString(address, attributes: run.attributes)
                linked.link = URL(string: lowered.hasPrefix("www.") ? "http://" + address : address)
                var rest = AttributedString(trailing + String(runText[cut...]), attributes: run.attributes)
                rest.link = nil
                ended += linked + rest
            } else {
                ended += AttributedString(content[run.range])
            }
        }
        content = ended
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
                guard isWebURL(link), URL(string: runText) == link else {
                    result += AttributedString(text[run.range])
                    continue
                }
                let cut = runText.firstIndex(where: \.isWhitespace) ?? runText.endIndex
                let (address, punctuation) = splitAutolinkTrailing(from: String(runText[..<cut]), cutAtSpace: cut != runText.endIndex)
                guard address != runText, let url = URL(string: address) else {
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
        for range in bareURLRanges(in: nsText) {
            let (address, _) = splitTrailingPunctuation(from: nsText.substring(with: range))
            guard let url = URL(string: address) else { continue }
            result += AttributedString(nsText.substring(with: NSRange(location: last, length: range.location - last)), attributes: plain)
            var linked = AttributedString(address, attributes: plain)
            linked.link = url
            result += linked
            last = range.location + (address as NSString).length
        }
        result += AttributedString(nsText.substring(from: last), attributes: plain)
        return result
    }

    // A bare URL runs to whitespace or a quote, keeping a balanced "(…)" or "[…]" but stopping at a ")" or
    // "]" that closes nothing, as in "(https://example.com/a.png),caption".
    private static func bareURLRanges(in nsText: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var scanned = 0
        for start in bareURLStartPattern.matches(in: nsText as String, range: NSRange(location: 0, length: nsText.length)) {
            guard start.range.location >= scanned else { continue }
            var end = NSMaxRange(start.range)
            var parentheses = 0
            var brackets = 0
            scan: while end < nsText.length {
                switch nsText.character(at: end) {
                case 0x28: parentheses += 1
                case 0x29 where parentheses == 0, 0x5D where brackets == 0, 0x22: break scan
                case 0x29: parentheses -= 1
                case 0x5B: brackets += 1
                case 0x5D: brackets -= 1
                case let unit:
                    if let scalar = Unicode.Scalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) { break scan }
                }
                end += 1
            }
            ranges.append(NSRange(location: start.range.location, length: end - start.range.location))
            scanned = end
        }
        return ranges
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
            let (address, trailing) = splitAutolinkTrailing(from: text)
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

    // What Foundation's autolinks keep that Reddit leaves as prose: non-ASCII punctuation such as "…", "”",
    // or "。", "]", and any ASCII punctuation they hid, as in "a.png.”" or "page." before a no-break space
    // (`cutAtSpace`). Otherwise Foundation already leaves ASCII punctuation out, and an explicit link such as
    // "[https://x/?q=why?](https://x/?q=why?)", which looks the same, keeps its own.
    private static func splitAutolinkTrailing(from token: String, cutAtSpace: Bool = false) -> (String, String) {
        let scalars = Array(token.unicodeScalars)
        var unclosed = Unclosed(scalars)
        var end = scalars.endIndex
        var overran = cutAtSpace
        while end > 0, CharacterSet.punctuationCharacters.contains(scalars[end - 1]) {
            let scalar = scalars[end - 1]
            let closesOpener = unclosed.closesOpener(scalar)
            let keptByFoundation = (!scalar.isASCII || scalar == "]") && !closesOpener
            let partOfURL = preservedURLCharacters.contains(scalar) || closesOpener
            guard keptByFoundation || (overran && !partOfURL) else { break }
            if keptByFoundation { overran = true }
            unclosed.drop(scalar)
            end -= 1
        }
        return split(scalars, at: end)
    }

    // `includingEmphasis` also trims GFM's trailing "*", "_", and "~", which a URL otherwise keeps.
    private static func splitTrailingPunctuation(from token: String, includingEmphasis: Bool = false) -> (String, String) {
        let scalars = Array(token.unicodeScalars)
        var unclosed = Unclosed(scalars)
        var end = scalars.endIndex
        while end > 0 {
            let scalar = scalars[end - 1]
            let isEmphasis = includingEmphasis && (scalar == "*" || scalar == "_" || scalar == "~")
            guard isEmphasis || (CharacterSet.punctuationCharacters.contains(scalar)
                && !preservedURLCharacters.contains(scalar) && !unclosed.closesOpener(scalar)) else { break }
            unclosed.drop(scalar)
            end -= 1
        }
        return split(scalars, at: end)
    }

    // Both splitters walk back once, keeping a running count, so a long run of ")" stays linear.
    private static let preservedURLCharacters = CharacterSet(charactersIn: "/-_~%+=&#@$*")

    // "(" minus ")" and "[" minus "]" in a URL; below zero, a closer closes nothing.
    private struct Unclosed {
        var parentheses = 0
        var brackets = 0

        init(_ scalars: [Unicode.Scalar]) {
            for scalar in scalars { count(scalar, by: 1) }
        }

        func closesOpener(_ scalar: Unicode.Scalar) -> Bool {
            (scalar == ")" && parentheses >= 0) || (scalar == "]" && brackets >= 0)
        }

        // Takes a trailing character off the URL.
        mutating func drop(_ scalar: Unicode.Scalar) {
            count(scalar, by: -1)
        }

        private mutating func count(_ scalar: Unicode.Scalar, by sign: Int) {
            switch scalar {
            case "(": parentheses += sign
            case ")": parentheses -= sign
            case "[": brackets += sign
            case "]": brackets -= sign
            default: break
            }
        }
    }

    private static func split(_ scalars: [Unicode.Scalar], at end: Int) -> (String, String) {
        var head = String.UnicodeScalarView()
        head.append(contentsOf: scalars[..<end])
        var tail = String.UnicodeScalarView()
        tail.append(contentsOf: scalars[end...])
        return (String(head), String(tail))
    }

    // The first GIF in reading order plays inline; later ones become links.
    // Tables past these bounds, in one table or across a body, show as text rows instead.
    static let maxTableColumns = 24
    static let maxTableCells = 1_500
    static let maxBodyTableCells = 3_000

    static func tableText(_ rows: [[AttributedString]]) -> AttributedString {
        var text = AttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 { text += AttributedString("\n") }
            for (column, cell) in row.enumerated() {
                if column > 0 { text += AttributedString(" | ") }
                text += cell
            }
        }
        return text
    }

    private static func limitTableCells(_ blocks: inout [MarkdownBlock]) {
        var budget = maxBodyTableCells
        func visit(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
            blocks.map { block in
                switch block {
                case .table(let table):
                    let cells = (table.rows.count + 1) * table.alignments.count
                    guard cells <= budget else { return .paragraph(tableText([table.header] + table.rows)) }
                    budget -= cells
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
                // Grid builds every cell up front, and a short body of pipes can ask for a vast sparse table.
                guard columns.count <= RedditMarkdown.maxTableColumns,
                      columns.count * children.count <= RedditMarkdown.maxTableCells else {
                    // Each cell keeps its column, so a row such as "x||z" stays "x |  | z"; a row pads only up
                    // to its own last cell, so the text never outgrows the body.
                    return .paragraph(RedditMarkdown.tableText(children.map { row in
                        var cells: [AttributedString] = []
                        for cell in row.children {
                            guard case .tableCell(let column) = cell.intent?.kind, column >= cells.count else { continue }
                            cells += Array(repeating: AttributedString(), count: column - cells.count)
                            cells.append(cell.content)
                        }
                        return cells
                    }))
                }
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
