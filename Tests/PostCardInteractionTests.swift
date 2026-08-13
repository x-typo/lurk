import Foundation
import Testing
@testable import Lurk

@Suite("Post card interaction routing")
struct PostCardInteractionTests {
    @Test("Horizontal drag suppresses detail until the gesture settles")
    func horizontalDragSuppressesDetail() {
        var state = PostCardInteractionState()

        #expect(state.updateDrag(translation: CGSize(width: 40, height: 2)) == 40)
        #expect(state.acceptedTapAction(.showDetail) == nil)
        #expect(
            state.endDrag(
                translation: CGSize(width: -140, height: 2),
                canHide: true
            ) == .hide
        )
        #expect(state.acceptedTapAction(.showDetail) == nil)

        let resetDetailSuppression = state.resetTapSuppression(
            ifGeneration: state.suppressionGeneration
        )
        #expect(resetDetailSuppression)
        #expect(state.acceptedTapAction(.showDetail) == .showDetail)
    }

    @Test("Horizontal drag suppresses external and media controls")
    func horizontalDragSuppressesOtherControls() {
        var state = PostCardInteractionState()
        let externalURL = URL(string: "https://example.com/story")!

        #expect(state.updateDrag(translation: CGSize(width: 30, height: 1)) == 30)
        #expect(state.acceptedTapAction(.openExternalURL(externalURL)) == nil)
        #expect(state.acceptedTapAction(.showMedia) == nil)
        #expect(
            state.endDrag(
                translation: CGSize(width: 140, height: 1),
                canHide: true
            ) == .openReddit
        )
    }

    @Test("Vertical scrolling suppresses card controls until the gesture settles")
    func verticalDragSuppressesControls() {
        var state = PostCardInteractionState()
        let externalURL = URL(string: "https://example.com/story")!

        #expect(state.updateDrag(translation: CGSize(width: 2, height: 40)) == nil)
        #expect(state.acceptedTapAction(.showDetail) == nil)
        #expect(state.acceptedTapAction(.openExternalURL(externalURL)) == nil)
        #expect(state.acceptedTapAction(.showMedia) == nil)
        #expect(
            state.endDrag(
                translation: CGSize(width: 2, height: 140),
                canHide: true
            ) == nil
        )
        #expect(state.acceptedTapAction(.showMedia) == nil)

        let resetVerticalSuppression = state.resetTapSuppression(
            ifGeneration: state.suppressionGeneration
        )
        #expect(resetVerticalSuppression)
        #expect(state.acceptedTapAction(.showMedia) == .showMedia)
    }

    @Test("A stale reset cannot clear suppression for a newer vertical drag")
    func staleResetCannotClearNewVerticalDrag() {
        var state = PostCardInteractionState()

        _ = state.updateDrag(translation: CGSize(width: 40, height: 2))
        #expect(
            state.endDrag(
                translation: CGSize(width: 60, height: 2),
                canHide: true
            ) == .reset
        )
        let staleGeneration = state.suppressionGeneration

        #expect(state.updateDrag(translation: CGSize(width: 2, height: 40)) == nil)
        #expect(state.suppressionGeneration != staleGeneration)
        let staleResetApplied = state.resetTapSuppression(ifGeneration: staleGeneration)
        #expect(!staleResetApplied)
        #expect(state.acceptedTapAction(.showMedia) == nil)
        #expect(state.acceptedTapAction(.showDetail) == nil)
    }

    @Test("Short and unavailable hide swipes reset without navigation")
    func incompleteSwipesReset() {
        var shortSwipe = PostCardInteractionState()
        _ = shortSwipe.updateDrag(translation: CGSize(width: 30, height: 1))
        #expect(
            shortSwipe.endDrag(
                translation: CGSize(width: 99, height: 1),
                canHide: true
            ) == .reset
        )

        var unavailableHide = PostCardInteractionState()
        _ = unavailableHide.updateDrag(translation: CGSize(width: -30, height: 1))
        #expect(
            unavailableHide.endDrag(
                translation: CGSize(width: -140, height: 1),
                canHide: false
            ) == .reset
        )
    }

    @Test("Swipe threshold remains strict")
    func thresholdBoundaryResets() {
        var right = PostCardInteractionState()
        _ = right.updateDrag(translation: CGSize(width: 30, height: 1))
        #expect(
            right.endDrag(
                translation: CGSize(width: 100, height: 1),
                canHide: true
            ) == .reset
        )

        var left = PostCardInteractionState()
        _ = left.updateDrag(translation: CGSize(width: -30, height: 1))
        #expect(
            left.endDrag(
                translation: CGSize(width: -100, height: 1),
                canHide: true
            ) == .reset
        )
    }
}
