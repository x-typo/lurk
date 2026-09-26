import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment thread")
struct CommentThreadTests {
    @Test("Rows flatten the tree in reading order with positional depth")
    func flattenOrder() {
        let nodes = [comment("a", [comment("b", [comment("c")]), more("t1_a", ["x"])]), comment("d")]
        let rows = CommentNode.rows(from: nodes, collapsed: [])
        #expect(rows.map(\.id) == ["a", "b", "c", "more:t1_a:x", "d"])
        #expect(rows.map(depth) == [0, 1, 2, 1, 0])
    }

    @Test("A collapsed comment hides its subtree and counts loaded and unloaded replies")
    func collapseHidesSubtree() {
        let nodes = [comment("a", [comment("b", [comment("c")]), more("t1_a", ["x", "y"], count: 5)]), comment("d")]
        let rows = CommentNode.rows(from: nodes, collapsed: ["a"])
        #expect(rows.map(\.id) == ["a", "d"])
        guard case .comment(_, _, let isCollapsed, let hiddenReplyCount) = rows[0],
              case .comment(_, _, let otherCollapsed, let otherHidden) = rows[1] else {
            Issue.record("Expected comment rows")
            return
        }
        #expect(isCollapsed)
        #expect(hiddenReplyCount == 7)
        #expect(!otherCollapsed)
        #expect(otherHidden == 0)
    }

    @Test("Nested collapse state survives collapsing and expanding an ancestor")
    func nestedCollapse() {
        let nodes = [comment("a", [comment("b", [comment("c")])])]
        #expect(ids(nodes, collapsed: ["a", "b"]) == ["a"])
        #expect(ids(nodes, collapsed: ["b"]) == ["a", "b"])
    }

    @Test("Muted authors are hidden with their replies, ignoring case")
    func mutedAuthorsHidden() {
        let nodes = [
            comment("a", [comment("b", [comment("c")], author: "Pest"), comment("d")]),
            comment("e", author: "AutoModerator"),
            comment("f"),
        ]
        #expect(ids(nodes, mutedUsers: ["pest", "automoderator"]) == ["a", "d", "f"])
        #expect(ids(nodes, mutedUsers: []) == ["a", "b", "c", "d", "e", "f"])
    }

    @Test("Pinned comments hide with their replies only while the setting is on")
    func pinnedCommentsHidden() {
        let nodes = [
            comment("pin", [comment("reply")], author: "AutoModerator", pinned: true),
            comment("a", [comment("b")]),
        ]
        #expect(ids(nodes, hidesPinned: true) == ["a", "b"])
        #expect(ids(nodes, hidesPinned: false) == ["pin", "reply", "a", "b"])
    }

    @Test("A collapsed comment's hidden-reply count skips muted subtrees")
    func collapsedCountSkipsMuted() {
        let nodes = [comment("a", [comment("b", [comment("c")], author: "Pest"), comment("d")])]
        let rows = CommentNode.rows(from: nodes, collapsed: ["a"], mutedUsers: ["pest"])
        guard case .comment(_, _, _, let hiddenReplyCount)? = rows.first else {
            Issue.record("Expected a comment row")
            return
        }
        #expect(hiddenReplyCount == 1)
    }

    @Test("Loaded replies replace their placeholder in place")
    func mergeReplacesPlaceholder() {
        let placeholder = CommentMore(parentID: "t1_a", count: 2, childIDs: ["x", "y"])
        let nodes = [comment("a", [comment("b"), .more(placeholder), comment("z")]), more("t3_p", ["q"], count: 9)]
        let merged = CommentNode.merging(
            [loaded("t1_a", comment("x")), loaded("t1_x", comment("x1")), loaded("t1_a", comment("y"))],
            replacing: placeholder,
            in: nodes
        )
        let rows = CommentNode.rows(from: merged, collapsed: [])
        #expect(rows.map(\.id) == ["a", "b", "x", "x1", "y", "z", "more:t3_p:q"])
        #expect(rows.map(depth) == [0, 1, 1, 2, 1, 1, 0])
    }

    @Test("Top-level placeholders are replaced by loaded top-level comments")
    func mergeTopLevel() {
        let placeholder = CommentMore(parentID: "t3_p", count: 2, childIDs: ["x", "y"])
        let merged = CommentNode.merging(
            [loaded("t3_p", comment("x")), loaded("t3_p", comment("y"))],
            replacing: placeholder,
            in: [comment("a"), .more(placeholder)]
        )
        #expect(ids(merged) == ["a", "x", "y"])
    }

    @Test("A reply whose parent loaded in an earlier batch attaches under that parent")
    func mergeAcrossBatches() {
        let first = CommentMore(parentID: "t1_root", count: 3, childIDs: ["a", "b", "c"])
        var nodes = [comment("root", [.more(first)])]
        let second = CommentMore(parentID: "t1_root", count: 1, childIDs: ["b"])
        nodes = CommentNode.merging(
            [loaded("t1_root", comment("a")), loaded("t1_root", .more(second))],
            replacing: first,
            in: nodes
        )
        nodes = CommentNode.merging([loaded("t1_a", comment("b"))], replacing: second, in: nodes)
        let rows = CommentNode.rows(from: nodes, collapsed: [])
        #expect(rows.map(\.id) == ["root", "a", "b"])
        #expect(rows.map(depth) == [0, 1, 2])
    }

    @Test("Repeated comments are skipped while their new replies are kept")
    func mergeKeepsRepliesOfRepeatedComments() {
        let placeholder = CommentMore(parentID: "t1_root", count: 2, childIDs: ["a", "n"])
        let nodes = [comment("root", [comment("a"), .more(placeholder)])]
        let merged = CommentNode.merging(
            [loaded("t1_root", comment("a")), loaded("t1_a", comment("n"))],
            replacing: placeholder,
            in: nodes
        )
        let rows = CommentNode.rows(from: merged, collapsed: [])
        #expect(rows.map(\.id) == ["root", "a", "n"])
        #expect(rows.map(depth) == [0, 1, 2])
    }

    @Test("Duplicate placeholders, orphans, and cycles are dropped")
    func mergeDropsUnplaceableNodes() {
        let placeholder = CommentMore(parentID: "t1_root", count: 1, childIDs: ["a"])
        let other = CommentMore(parentID: "t1_root", count: 3, childIDs: ["z"])
        let nodes = [comment("root", [.more(placeholder), .more(other)])]
        let merged = CommentNode.merging(
            [
                loaded("t1_root", comment("a")),
                loaded("t1_root", .more(other)),
                loaded("t1_root", .more(placeholder)),
                loaded("t1_missing", comment("orphan")),
                loaded("t1_c2", comment("c1")),
                loaded("t1_c1", comment("c2")),
            ],
            replacing: placeholder,
            in: nodes
        )
        #expect(ids(merged) == ["root", "a", other.id])
    }

    @Test("Indentation grows per level and stops at the cap")
    func indentation() {
        #expect(CommentRails.indent(for: 0) == 0)
        #expect(CommentRails.indent(for: 1) == 16)
        #expect(CommentRails.indent(for: 3) == 36)
        #expect(CommentRails.indent(for: Comment.maxIndentDepth + 5) == CommentRails.indent(for: Comment.maxIndentDepth))
    }

    @Test("Short and long left swipes vote; a right swipe replies")
    func swipeStages() {
        #expect(CommentSwipeState.stage(for: 0) == .none)
        #expect(CommentSwipeState.stage(for: -59) == .none)
        #expect(CommentSwipeState.stage(for: -60) == .upvote)
        #expect(CommentSwipeState.stage(for: -139) == .upvote)
        #expect(CommentSwipeState.stage(for: -140) == .downvote)
        #expect(CommentSwipeState.stage(for: 59) == .none)
        #expect(CommentSwipeState.stage(for: 60) == .reply)
    }

    @Test("A drag that starts vertical stays a scroll")
    func verticalDragLocks() {
        var state = CommentSwipeState()
        #expect(state.updateDrag(translation: CGSize(width: 2, height: 30)) == nil)
        #expect(state.updateDrag(translation: CGSize(width: -150, height: 40)) == nil)
        #expect(state.endDrag(translation: CGSize(width: -150, height: 40)) == .none)
    }

    @Test("A horizontal drag stays horizontal and is clamped")
    func horizontalDragLocks() {
        var state = CommentSwipeState()
        #expect(state.updateDrag(translation: CGSize(width: -30, height: 2)) == -30)
        #expect(state.updateDrag(translation: CGSize(width: -80, height: 90)) == -80)
        #expect(state.updateDrag(translation: CGSize(width: -400, height: 0)) == -200)
        #expect(state.endDrag(translation: CGSize(width: -400, height: 0)) == .downvote)
        #expect(state.updateDrag(translation: CGSize(width: 300, height: 0)) == 120)
        #expect(state.endDrag(translation: CGSize(width: 300, height: 0)) == .reply)
    }

    private func ids(
        _ nodes: [CommentNode],
        collapsed: Set<String> = [],
        mutedUsers: Set<String> = [],
        hidesPinned: Bool = false
    ) -> [String] {
        CommentNode.rows(from: nodes, collapsed: collapsed, mutedUsers: mutedUsers, hidesPinned: hidesPinned).map(\.id)
    }

    private func depth(_ row: CommentRow) -> Int {
        switch row {
        case .comment(_, let depth, _, _): depth
        case .more(_, let depth): depth
        }
    }

    private func comment(
        _ id: String,
        _ replies: [CommentNode] = [],
        author: String = "reader",
        pinned: Bool = false
    ) -> CommentNode {
        .comment(Lurk.Comment(id: id, author: author, body: "body", score: 1, createdUtc: 0,
                              isSubmitter: false, isPinned: pinned), replies: replies)
    }

    private func more(_ parentID: String, _ childIDs: [String], count: Int? = nil) -> CommentNode {
        .more(CommentMore(parentID: parentID, count: count ?? childIDs.count, childIDs: childIDs))
    }

    private func loaded(_ parentID: String, _ node: CommentNode) -> LoadedCommentNode {
        LoadedCommentNode(parentID: parentID, node: node)
    }
}
