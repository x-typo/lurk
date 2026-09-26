import SwiftUI
import UIKit

struct PostShareSheet: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = PostShareItemSource(url: url, title: title)
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// Deliberately provides no link metadata: when an app supplies its own, Messages uses it
// instead of fetching Reddit's preview card for the link, the way Safari's share gets it.
private final class PostShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String {
        title
    }
}
