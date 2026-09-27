import Observation
import SwiftUI

// Reply and edit sheets report unsent text here. A thread link from another app replaces whatever is on
// screen, including those sheets, so it waits until no text is unsent.
@Observable
final class UnsentTextTracker {
    private var editors: Set<UUID> = []

    var hasUnsentText: Bool { !editors.isEmpty }

    func update(_ editor: UUID, hasUnsentText: Bool) {
        if hasUnsentText {
            editors.insert(editor)
        } else {
            editors.remove(editor)
        }
    }
}

extension View {
    // Tracks an editor's unsent text while it's on screen; screens without a tracker are unaffected.
    func tracksUnsentText(_ hasUnsentText: Bool) -> some View {
        modifier(UnsentTextReporter(hasUnsentText: hasUnsentText))
    }
}

private struct UnsentTextReporter: ViewModifier {
    let hasUnsentText: Bool
    @Environment(UnsentTextTracker.self) private var tracker: UnsentTextTracker?
    @State private var editor = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: hasUnsentText, initial: true) { _, hasUnsentText in
                tracker?.update(editor, hasUnsentText: hasUnsentText)
            }
            .onDisappear {
                tracker?.update(editor, hasUnsentText: false)
            }
    }
}
