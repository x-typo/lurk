import SwiftUI

extension View {
    // Close or Done at the bottom center, within thumb reach. It's an app-owned button, not a `.status`
    // toolbar item: on iOS 26 and later the toolbar's glass capsule has a 5–6 pt rim that animates on a
    // tap but never runs the action.
    func bottomCloseButton(_ title: String = "Close", action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            Button(action: action) {
                Text(title)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .contentShape(Capsule())
            }
            .bottomCloseButtonStyle()
            .foregroundStyle(Theme.primary)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func bottomCloseButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.plain)
                .background(Theme.surfaceElevated, in: Capsule())
        }
    }
}
