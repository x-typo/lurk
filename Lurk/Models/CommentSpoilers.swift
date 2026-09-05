import Foundation

enum CommentSpoilers {
    enum Part: Equatable {
        case text(String)
        case spoiler(id: Int, content: String)
    }

    static func parse(_ text: String) -> [Part] {
        var parts: [Part] = []
        var plainStart = text.startIndex
        var cursor = text.startIndex
        var spoilerID = 0

        while cursor < text.endIndex {
            if let codeEnd = codeEnd(at: cursor, in: text) {
                cursor = codeEnd
                continue
            }
            guard text[cursor...].hasPrefix(">!"), !isEscaped(cursor, in: text) else {
                cursor = text.index(after: cursor)
                continue
            }

            if plainStart < cursor {
                parts.append(.text(String(text[plainStart..<cursor])))
            }
            let contentStart = text.index(cursor, offsetBy: 2)
            var end = contentStart
            var nesting = 1
            while end < text.endIndex {
                if let codeEnd = codeEnd(at: end, in: text) {
                    end = codeEnd
                    continue
                }
                if (text[end...].hasPrefix(">!") || text[end...].hasPrefix("!<")),
                   !isEscaped(end, in: text) {
                    if text[end...].hasPrefix(">!") {
                        nesting += 1
                        end = text.index(end, offsetBy: 2)
                        continue
                    }
                    if text[end...].hasPrefix("!<") {
                        nesting -= 1
                        if nesting == 0 { break }
                        end = text.index(end, offsetBy: 2)
                        continue
                    }
                }
                end = text.index(after: end)
            }
            // An unfinished spoiler stays concealed through the end of the body.
            parts.append(.spoiler(id: spoilerID, content: String(text[contentStart..<end])))
            spoilerID += 1
            cursor = end == text.endIndex ? end : text.index(end, offsetBy: 2)
            plainStart = cursor
        }
        if plainStart < text.endIndex {
            parts.append(.text(String(text[plainStart...])))
        }
        return parts
    }

    private static func codeEnd(at start: String.Index, in text: String) -> String.Index? {
        let marker = text[start]
        guard marker == "`" || marker == "~", !isEscaped(start, in: text) else { return nil }
        if start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous] != marker || isEscaped(previous, in: text) else { return nil }
        }
        let openingEnd = text[start...].firstIndex(where: { $0 != marker }) ?? text.endIndex
        let width = text.distance(from: start, to: openingEnd)
        let fenced = width >= 3 && isFenceStart(start, in: text)
        guard marker == "`" || fenced else { return nil }

        var cursor = openingEnd
        while cursor < text.endIndex {
            guard let next = text[cursor...].firstIndex(of: marker) else { break }
            let runEnd = text[next...].firstIndex(where: { $0 != marker }) ?? text.endIndex
            let runWidth = text.distance(from: next, to: runEnd)
            if fenced {
                let lineEnd = text[runEnd...].firstIndex(of: "\n") ?? text.endIndex
                if runWidth >= width, isFenceStart(next, in: text),
                   text[runEnd..<lineEnd].allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" }) {
                    return runEnd
                }
            } else if runWidth == width {
                return runEnd
            }
            cursor = runEnd
        }
        return fenced ? text.endIndex : nil
    }

    private static func isFenceStart(_ index: String.Index, in text: String) -> Bool {
        let lineStart = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let prefix = text[lineStart..<index]
        return prefix.count <= 3 && prefix.allSatisfy { $0 == " " }
    }

    static func selectionText(from text: String, revealed: Set<Int>) -> String {
        parse(text).map { part in
            switch part {
            case .text(let text): text
            case .spoiler(let id, let content): revealed.contains(id) ? content : "[Spoiler hidden]"
            }
        }.joined()
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        var backslashes = 0
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "\\" else { break }
            backslashes += 1
        }
        return backslashes % 2 == 1
    }
}
