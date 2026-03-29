import Foundation

// MARK: - API Response Types

struct RedditListing: Decodable {
    let data: ListingData
}

struct ListingData: Decodable {
    let after: String?
    let children: [PostWrapper]
}

struct PostWrapper: Decodable {
    let data: Post
}

struct Post: Identifiable, Decodable {
    let id: String
    let title: String
    let author: String
    let subreddit: String
    let subredditNamePrefixed: String
    let score: Int
    let numComments: Int
    let createdUtc: TimeInterval
    let permalink: String
    let url: String
    let selftext: String
    let isSelf: Bool
    let isVideo: Bool
    let stickied: Bool
    let over18: Bool
    let postHint: String?
    let media: Media?
    let preview: Preview?
    let galleryData: GalleryData?
    let mediaMetadata: [String: MediaMetadataItem]?
}

// MARK: - Media Types

struct Media: Decodable {
    let redditVideo: RedditVideo?
}

struct RedditVideo: Decodable {
    let fallbackUrl: String
    let width: Int
    let height: Int
}

struct Preview: Decodable {
    let images: [PreviewImage]?
}

struct PreviewImage: Decodable {
    let source: ImageSource
}

struct ImageSource: Decodable {
    let url: String
    let width: Int
    let height: Int

    var decodedUrl: String {
        url.replacingOccurrences(of: "&amp;", with: "&")
    }
}

struct GalleryData: Decodable {
    let items: [GalleryItem]?
}

struct GalleryItem: Decodable {
    let mediaId: String
}

struct MediaMetadataItem: Decodable {
    let s: MediaMetadataSource?
}

struct MediaMetadataSource: Decodable {
    let u: String?
    let x: Int?
    let y: Int?

    var decodedUrl: String? {
        u?.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Enums

enum SortType: String, CaseIterable {
    case hot, new, top, rising
}

enum TimeFilter: String, CaseIterable {
    case hour, day, week, month, year, all
}

// MARK: - Computed Properties

extension Post {
    var imageURL: URL? {
        if let source = preview?.images?.first?.source {
            return URL(string: source.decodedUrl)
        }
        if let firstItem = galleryData?.items?.first,
           let meta = mediaMetadata?[firstItem.mediaId],
           let urlStr = meta.s?.decodedUrl {
            return URL(string: urlStr)
        }
        return nil
    }

    var imageAspectRatio: CGFloat? {
        if let source = preview?.images?.first?.source, source.height > 0 {
            return CGFloat(source.width) / CGFloat(source.height)
        }
        return nil
    }

    var videoURL: URL? {
        guard isVideo, let video = media?.redditVideo else { return nil }
        return URL(string: video.fallbackUrl)
    }

    var isGallery: Bool {
        (galleryData?.items?.count ?? 0) > 1
    }

    var galleryCount: Int {
        galleryData?.items?.count ?? 0
    }

    var redditURL: URL {
        URL(string: "https://www.reddit.com\(permalink)")!
    }
}
