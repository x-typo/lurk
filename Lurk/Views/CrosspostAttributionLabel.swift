import SwiftUI

struct CrosspostAttributionLabel: View {
    let crosspost: CrosspostContent

    var body: some View {
        Label(
            "Crossposted from \(crosspost.subredditNamePrefixed ?? "another community")",
            systemImage: "arrow.triangle.branch"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.leading)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
