import Foundation

nonisolated struct SavedCommentListing: Decodable {
    let data: SavedCommentListingData
}

struct SavedCommentListingData: Decodable {
    let after: String?
    let children: [SavedCommentWrapper]
}

struct SavedCommentWrapper: Decodable {
    let data: SavedComment
}

struct SavedComment: Identifiable, Decodable {
    let id: String
    let author: String
    let body: String
    let score: Int
    let createdUtc: TimeInterval
    let subreddit: String
    let subredditNamePrefixed: String
    let permalink: String
    let linkTitle: String
}
