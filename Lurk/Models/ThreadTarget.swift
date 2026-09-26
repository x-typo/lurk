import Foundation

// A post, and optionally one of its comments, read from a Reddit link so the thread opens in Lurk.
struct ThreadTarget: Identifiable, Hashable {
    let postID: String
    var commentID: String? = nil
    // Opened on Reddit if the thread can't load.
    var sourceURL: URL? = nil

    var id: String { commentID.map { "\(postID)/\($0)" } ?? postID }

    var wholePost: ThreadTarget { ThreadTarget(postID: postID, sourceURL: sourceURL) }
}

extension ThreadTarget {
    // Accepts Reddit URLs and permalinks shaped `/r/<sub>/comments/<post>/<slug>/<comment>/`, with or
    // without the comment and query items such as `?context=3`.
    init?(url: URL) {
        if let host = url.host?.lowercased(), host != "reddit.com", !host.hasSuffix(".reddit.com") {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(of: "comments"),
              index + 1 < parts.count,
              Comment.isRedditID(parts[index + 1]) else { return nil }
        postID = parts[index + 1]
        sourceURL = url
        let commentIndex = index + 3
        if commentIndex < parts.count, Comment.isRedditID(parts[commentIndex]) {
            commentID = parts[commentIndex]
        }
    }

    init?(permalink: String) {
        guard let url = URL(string: permalink.hasPrefix("/") ? "https://www.reddit.com\(permalink)" : permalink) else {
            return nil
        }
        self.init(url: url)
    }
}
