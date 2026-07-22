import Foundation

nonisolated struct UserCommentListing: Decodable {
    let data: UserCommentListingData
}

struct UserCommentListingData: Decodable {
    let after: String?
    let children: [UserCommentWrapper]
}

struct UserCommentWrapper: Decodable {
    let data: UserComment
}

struct UserComment: Identifiable, Decodable {
    let id: String
    let author: String
    var body: String
    let score: Int
    let createdUtc: TimeInterval
    let subreddit: String
    let subredditNamePrefixed: String
    let permalink: String
    let linkTitle: String
    let linkPermalink: String?
    let parentId: String?
    let parentAuthor: String?

    var actionLine: String {
        if parentId?.hasPrefix("t1_") == true, let parentAuthor, !parentAuthor.isEmpty {
            return "replied to \(parentAuthor)"
        }
        return "commented"
    }

    var redditURL: URL {
        if let url = URL(string: permalink), url.scheme != nil {
            return url
        }
        return URL(string: "https://www.reddit.com\(normalizedPath(permalink))")!
    }

    var postURL: URL? {
        if let linkPermalink, !linkPermalink.isEmpty {
            if let url = URL(string: linkPermalink), let scheme = url.scheme, !scheme.isEmpty {
                return url
            }
            return URL(string: "https://www.reddit.com\(normalizedPath(linkPermalink))")
        }

        let components = normalizedPath(permalink)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let commentsIndex = components.firstIndex(of: "comments"),
              components.count > commentsIndex + 2 else {
            return nil
        }

        let postComponentEnd = min(commentsIndex + 3, components.count)
        let postPath = "/" + components[0..<postComponentEnd].joined(separator: "/") + "/"
        return URL(string: "https://www.reddit.com\(postPath)")
    }

    private func normalizedPath(_ rawPath: String) -> String {
        rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
    }
}
