import LinkPresentation
import SwiftUI
import UIKit

struct PostShareSheet: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let imageURL: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = PostShareItemSource(url: url, title: title, imageURL: imageURL)
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private final class PostShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String
    private let imageURL: URL?

    init(url: URL, title: String, imageURL: URL?) {
        self.url = url
        self.title = title
        self.imageURL = imageURL
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

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let imageURL {
            metadata.imageProvider = NSItemProvider(contentsOf: imageURL)
        }
        return metadata
    }
}
