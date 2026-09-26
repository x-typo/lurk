import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Comment thread")
struct CommentThreadTests {
    @Test("Rows flatten the tree in reading order")
    func flattenOrder() {
        let nodes = [comment("a", 0, [comment("b", 1, [comment("c", 2)]), more("t1_a", 1, ["x"])]), comment("d", 0)]
        #expect(ids(nodes) == ["a", "b", "c", "more:t1_a:x", "d"])
    }

    @Test("A collapsed comment hides its subtree and counts loaded and unloaded replies")
    func collapseHidesSubtree() {
        let nodes = [comment("a", 0, [comment("b", 1, [comment("c", 2)]), more("t1_a", 1, ["x", "y"], count: 5)]), comment("d", 0)]
        let rows = CommentNode.rows(from: nodes, collapsed: ["a"])
        #expect(rows.map(\.id) == ["a", "d"])
        guard case .comment(_, let isCollapsed, let hiddenReplyCount) = rows[0],
              case .comment(_, let otherCollapsed, let otherHidden) = rows[1] else {
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
        let nodes = [comment("a", 0, [comment("b", 1, [comment("c", 2)])])]
        #expect(ids(nodes, collapsed: ["a", "b"]) == ["a"])
        #expect(ids(nodes, collapsed: ["b"]) == ["a", "b"])
    }

    @Test("Loaded replies replace only their placeholder")
    func spliceReplacesPlaceholder() {
        let placeholder = CommentMore(parentID: "t1_a", depth: 1, count: 2, childIDs: ["x", "y"])
        let nodes = [comment("a", 0, [comment("b", 1), .more(placeholder)]), more("t3_p", 0, ["z"], count: 9)]
        let spliced = CommentNode.replacing(moreID: placeholder.id, with: [comment("x", 1), comment("y", 1)], in: nodes)
        #expect(ids(spliced) == ["a", "b", "x", "y", "more:t3_p:z"])
    }

    @Test("Duplicate comments are removed with their replies")
    func removesDuplicates() {
        let loaded = [comment("b", 1, [comment("c", 2)]), comment("x", 1, [comment("b", 2)])]
        #expect(ids(CommentNode.removingComments(["b"], from: loaded)) == ["x"])
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

    private func ids(_ nodes: [CommentNode], collapsed: Set<String> = []) -> [String] {
        CommentNode.rows(from: nodes, collapsed: collapsed).map(\.id)
    }

    private func comment(_ id: String, _ depth: Int, _ replies: [CommentNode] = []) -> CommentNode {
        .comment(Lurk.Comment(id: id, author: "reader", body: "body", score: 1, createdUtc: 0,
                              depth: depth, isSubmitter: false), replies: replies)
    }

    private func more(_ parentID: String, _ depth: Int, _ childIDs: [String], count: Int? = nil) -> CommentNode {
        .more(CommentMore(parentID: parentID, depth: depth, count: count ?? childIDs.count, childIDs: childIDs))
    }
}
