import Foundation

// One block of a Reddit body: headings, lists, tables, quotes, and code keep their structure, and
// inline styling and links stay in each block's text.
indirect enum MarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case quote([MarkdownBlock])
    case list(ordered: Bool, items: [MarkdownListItem])
    case code(String)
    case table(MarkdownTable)
    case rule
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

enum RedditMarkdown {
    // A GFM table's delimiter row, such as ":-:|:-:" or "|---|---|".
    private static let tableDelimiterPattern = try! NSRegularExpression(
        pattern: #"^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|?\s*$"#,
        options: .anchorsMatchLines
    )

    // `continuingLine` marks text that follows media or a hidden spoiler on the same source line.
    static func blocks(from text: String, continuingLine: Bool = false) -> [MarkdownBlock] {
        let source = continuingLine ? escapingLeadingBlockMarker(text) : text
        guard let parsed = try? AttributedString(
            markdown: normalized(source),
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            return [.paragraph(AttributedString(text))]
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
        let blocks = root.children.compactMap(\.block)
        // A lone marker, such as "2." before a hidden spoiler, parses to nothing; show it as written. A lone
        // quote marker before media stays out of sight, as its empty quote was before.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if blocks.isEmpty, !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == ">" || $0.isWhitespace }) {
            return [.paragraph(AttributedString(trimmed))]
        }
        return blocks
    }

    // Reddit makes "#Title" a heading; CommonMark needs a space after the marker. Fenced code and
    // table rows such as "#|Episode" are left alone.
    static func normalized(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let fenced = fencedLines(lines, unclosedRunToEnd: true)
        let tables = tableLines(lines)
        return lines.enumerated().map { index, line in
            if fenced.contains(index) { return String(line) }
            // Foundation reads "^[text](url)" as its attribute syntax and drops the link; on Reddit it's a
            // caret and a link. Only that shape is escaped, so a regex such as "^[a-z]+" in code is untouched.
            let line = line.replacingOccurrences(
                of: #"\^\[(?=[^\]\n]*\]\(https?://)"#, with: #"\\^["#, options: .regularExpression
            )
            return tables.contains(index) ? line : spacedHeading(Substring(line)) ?? line
        }
        .joined(separator: "\n")
    }

    // Indexes of the lines in tables: each header row, its delimiter row, and the rows after it. As on
    // Reddit, a row carries a pipe, so a line without one, such as "#Next" or a closing code fence, ends
    // the table. A table-shaped example in code counts too, which keeps its links from becoming media.
    static func tableLines(_ lines: [Substring]) -> Set<Int> {
        var result: Set<Int> = []
        var index = 1
        while index < lines.count {
            guard isTableDelimiter(lines[index]), hasCellPipe(lines[index - 1]) else {
                index += 1
                continue
            }
            result.formUnion([index - 1, index])
            index += 1
            while index < lines.count, hasCellPipe(lines[index]) {
                result.insert(index)
                index += 1
            }
        }
        return result
    }

    // A giphy embed's own "|", as in "![gif](giphy|abc)", doesn't make a line a table row.
    private static func hasCellPipe(_ line: Substring) -> Bool {
        line.replacingOccurrences(of: #"!\[gif\]\(giphy\|[^)]*\)"#, with: "", options: .regularExpression).contains("|")
    }

    // Indexes of fenced code lines, fences included. Quote and list containers aren't modeled, so a fence
    // never closed may have ended with its quote: media extraction leaves it out, while the heading
    // normalizer (`unclosedRunToEnd`) treats it as code to the end, as CommonMark does at the top level.
    static func fencedLines(_ lines: [Substring], unclosedRunToEnd: Bool = false) -> Set<Int> {
        var result: Set<Int> = []
        var index = 0
        while index < lines.count {
            guard let open = openingFence(blockContent(of: lines[index])) else {
                index += 1
                continue
            }
            guard let close = lines[(index + 1)...].firstIndex(where: { isClosingFence(blockContent(of: $0), of: open) }) else {
                if unclosedRunToEnd {
                    result.formUnion(index..<lines.count)
                    break
                }
                index += 1
                continue
            }
            result.formUnion(index...close)
            index = close + 1
        }
        return result
    }

    private static func spacedHeading(_ line: Substring) -> String? {
        let indent = line.prefix(while: { $0 == " " })
        guard indent.count <= 3 else { return nil }
        let body = line.dropFirst(indent.count)
        let hashes = body.prefix(while: { $0 == "#" })
        let rest = body.dropFirst(hashes.count)
        guard (1...6).contains(hashes.count), let next = rest.first, !next.isWhitespace else { return nil }
        return String(indent) + hashes + " " + rest
    }

    // A line's text after its quote and list markers, where a code fence can start.
    private static func blockContent(of line: Substring) -> Substring {
        var content = line.drop(while: { $0 == " " || $0 == "\t" })
        while true {
            if content.first == ">" {
                content = content.dropFirst().drop(while: { $0 == " " })
            } else if let marker = content.first, "*+-".contains(marker), content.dropFirst().first == " " {
                content = content.dropFirst().drop(while: { $0 == " " })
            } else if let afterDigits = orderedMarkerEnd(content), content[afterDigits...].first == " " {
                content = content[afterDigits...].drop(while: { $0 == " " })
            } else {
                return content
            }
        }
    }

    // The index after an ordered-list marker such as "12." or "3)".
    private static func orderedMarkerEnd(_ text: Substring) -> Substring.Index? {
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...9).contains(digits.count), digits.endIndex < text.endIndex,
              text[digits.endIndex] == "." || text[digits.endIndex] == ")" else { return nil }
        return text.index(after: digits.endIndex)
    }

    private static func openingFence(_ content: Substring) -> (marker: Character, length: Int)? {
        guard let marker = content.first, marker == "`" || marker == "~" else { return nil }
        let length = content.prefix(while: { $0 == marker }).count
        // A backtick fence's info string can't hold a backtick, so "```npm i```" is inline code.
        guard length >= 3, marker == "~" || !content.dropFirst(length).contains("`") else { return nil }
        return (marker, length)
    }

    private static func isClosingFence(_ content: Substring, of open: (marker: Character, length: Int)) -> Bool {
        let length = content.prefix(while: { $0 == open.marker }).count
        return length >= open.length && content.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    private static func isTableDelimiter(_ line: Substring) -> Bool {
        let text = String(line)
        return tableDelimiterPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // Text after media or a hidden spoiler is mid-line in the source, so a leading "-", "#", or "1."
    // there is prose, not a list or heading.
    static func escapingLeadingBlockMarker(_ text: String) -> String {
        let start = text.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = start.first, first != "\n" else { return text }
        let firstLine = start.prefix(while: { $0 != "\n" })
        // "*" opens a block only as a list marker or a "***" rule; "**bold**" is inline.
        let opensBlock = "-+#>".contains(first) || (first == "*"
            && ((firstLine.dropFirst().first?.isWhitespace ?? true) || firstLine.allSatisfy { $0 == "*" || $0 == " " }))
        if opensBlock {
            return "\\" + start
        }
        if let afterMarker = orderedMarkerEnd(start) {
            let delimiter = start.index(before: afterMarker)
            return String(start[..<delimiter]) + "\\" + start[delimiter...]
        }
        return String(start)
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
        // "![clip](https://…)" to a page that isn't an image keeps its target as a link.
        for (imageURL, range) in content.runs[\.imageURL].reversed() {
            guard let imageURL, content[range].link == nil, ["http", "https"].contains(imageURL.scheme?.lowercased()) else { continue }
            content[range].link = imageURL
        }
        return content
    }

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
