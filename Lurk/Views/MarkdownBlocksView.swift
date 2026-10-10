import SwiftUI

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, font: font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let font: Font

    var body: some View {
        switch block {
        case .paragraph(let text):
            MarkdownText(text: text, font: font)
        case .heading(let level, let text):
            MarkdownText(text: text, font: Self.headingFont(level: level, body: font))
        case .quote(let blocks):
            MarkdownBlocksView(blocks: blocks, font: font)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.primary)
                        .frame(width: 3)
                }
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: ordered ? "\(item.ordinal)." : "•")
                            .font(font)
                            .foregroundStyle(Theme.textSecondary)
                        MarkdownBlocksView(blocks: item.blocks, font: font)
                    }
                }
            }
        case .code(let code):
            // Wraps instead of scrolling sideways, which would compete with comment swipes.
            Text(verbatim: code)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
        case .table(let table):
            MarkdownTableView(table: table, font: font)
        case .rule:
            Divider().background(Theme.border).padding(.vertical, 4)
        }
    }

    private static func headingFont(level: Int, body: Font) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline
        default: body.weight(.semibold)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let font: Font

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            if !table.header.isEmpty {
                GridRow {
                    ForEach(table.alignments.indices, id: \.self) { column in
                        MarkdownText(text: table.header[column], font: font.weight(.semibold))
                            .multilineTextAlignment(Self.textAlignment(table.alignments[column]))
                            .gridColumnAlignment(Self.columnAlignment(table.alignments[column]))
                    }
                }
                Divider()
                    .background(Theme.border)
                    .gridCellUnsizedAxes(.horizontal)
            }
            ForEach(table.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(table.alignments.indices, id: \.self) { column in
                        MarkdownText(text: table.rows[row][column], font: font)
                            .multilineTextAlignment(Self.textAlignment(table.alignments[column]))
                    }
                }
            }
        }
    }

    private static func columnAlignment(_ alignment: PresentationIntent.TableColumn.Alignment) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }

    private static func textAlignment(_ alignment: PresentationIntent.TableColumn.Alignment) -> TextAlignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

private struct MarkdownText: View {
    let text: AttributedString
    let font: Font

    var body: some View {
        Text(Self.styledLinks(text))
            .font(font)
            .foregroundStyle(Theme.text)
    }

    // Links match the rest of Lurk's link styling; the environment's openURL handles taps.
    private static func styledLinks(_ text: AttributedString) -> AttributedString {
        var styled = text
        let linkRanges = styled.runs[\.link].compactMap { link, range in link == nil ? nil : range }
        for range in linkRanges {
            styled[range].foregroundColor = Theme.primary
            styled[range].underlineStyle = Text.LineStyle.single
        }
        return styled
    }
}
