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
    // Accepts Reddit URLs and permalinks shaped `/r/<sub>/comments/<post>/<slug>/<comment>/` (or
    // `/user/<name>/…`, `/u/<name>/…`, `/comments/<post>/…`), with or without the comment and query items
    // such as `?context=3`. Segments are matched by position, so a subreddit named "comments" still works.
    init?(url: URL) {
        if let host = url.host?.lowercased(), host != "reddit.com", !host.hasSuffix(".reddit.com") {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        let index: Int
        switch parts.first?.lowercased() {
        case "r", "user", "u": index = 2
        case "comments": index = 0
        default: return nil
        }
        guard index + 1 < parts.count,
              parts[index] == "comments",
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

// Other apps open Reddit threads in Lurk with `lurk://open?url=<percent-encoded Reddit link>` (Rakuroku's
// contract). Once Lurk registers the scheme, iOS hands it every `lurk://` link, so the sender's own
// browser fallback never runs; a Reddit link Lurk can't open as a thread goes to the browser instead.
enum LurkLink: Equatable {
    // https on reddit.com, www.reddit.com, or old.reddit.com, shaped `/r/<subreddit>/comments/<post>/` with an
    // optional slug.
    case thread(ThreadTarget)
    // Any other https link on reddit.com, a subdomain of it, or redd.it.
    case web(URL)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "lurk", url.host?.lowercased() == "open",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let link = URL(string: value),
              link.scheme?.lowercased() == "https",
              let host = link.host?.lowercased(),
              host == "reddit.com" || host.hasSuffix(".reddit.com") || host == "redd.it" else { return nil }
        let parts = link.pathComponents.filter { $0 != "/" }
        if ["reddit.com", "www.reddit.com", "old.reddit.com"].contains(host),
           (4...5).contains(parts.count),
           parts[0].lowercased() == "r",
           parts[2] == "comments",
           Comment.isRedditID(parts[3]) {
            self = .thread(ThreadTarget(postID: parts[3], sourceURL: link))
        } else {
            self = .web(link)
        }
    }
}
