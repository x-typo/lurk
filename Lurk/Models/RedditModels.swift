import CoreGraphics
import Foundation

// MARK: - API Response Types

struct RedditListing: Decodable {
    let data: ListingData
}

struct ListingData: Decodable {
    let after: String?
    let children: [PostWrapper]

    private struct LossyPostWrapper: Decodable {
        let wrapped: PostWrapper?
        init(from decoder: Decoder) throws {
            wrapped = try? PostWrapper(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case after, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        after = try container.decodeIfPresent(String.self, forKey: .after)
        let lossy = try container.decode([LossyPostWrapper].self, forKey: .children)
        let decoded = lossy.compactMap(\.wrapped)
        if !lossy.isEmpty && decoded.isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .children,
                in: container,
                debugDescription: "All \(lossy.count) children failed to decode"
            )
        }
        children = decoded
    }
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

    static let filteredKeywords: Set<String> = [
        "Artemis"
    ]
}

// MARK: - Media Types

struct Media: Decodable {
    let redditVideo: RedditVideo?
}

struct RedditVideo: Decodable {
    let fallbackUrl: String
    let hlsUrl: String?
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
    let e: String?
    let s: MediaMetadataSource?

    var isAnimated: Bool {
        e == "AnimatedImage"
    }
}

struct MediaMetadataSource: Decodable {
    let u: String?
    let gif: String?
    let x: Int?
    let y: Int?

    var decodedUrl: String? {
        (u ?? gif)?.replacingOccurrences(of: "&amp;", with: "&")
    }
}

struct GalleryMedia: Identifiable {
    let id: Int
    let url: URL
    let isAnimated: Bool
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
    var youtubeVideoID: String? {
        guard let parsedURL = URL(string: url) else { return nil }
        return Self.youtubeVideoID(from: parsedURL)
    }

    var isYouTubeVideo: Bool {
        youtubeVideoID != nil
    }

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
        if let hlsUrl = video.hlsUrl, let url = URL(string: hlsUrl) {
            return url
        }
        return URL(string: video.fallbackUrl)
    }

    var videoAspectRatio: CGFloat? {
        if let video = media?.redditVideo, video.height > 0 {
            return CGFloat(video.width) / CGFloat(video.height)
        }
        return nil
    }

    var isGallery: Bool {
        galleryCount > 1
    }

    var galleryCount: Int {
        galleryData?.items?.count ?? 0
    }

    var galleryItems: [GalleryMedia] {
        guard let items = galleryData?.items else { return [] }
        var result: [GalleryMedia] = []
        for item in items {
            guard let meta = mediaMetadata?[item.mediaId],
                  let urlStr = meta.s?.decodedUrl,
                  let url = URL(string: urlStr) else { continue }
            result.append(GalleryMedia(id: result.count, url: url, isAnimated: meta.isAnimated))
        }
        return result
    }

    var redditURL: URL {
        URL(string: "https://www.reddit.com\(permalink)")!
    }

    var matchesFilteredKeyword: Bool {
        Post.filteredKeywords.contains { title.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        if normalizedHost == "youtu.be" {
            return sanitizedYouTubeVideoID(
                url.pathComponents.first { $0 != "/" && !$0.isEmpty }
            )
        }

        guard normalizedHost == "youtube.com" || normalizedHost.hasSuffix(".youtube.com") else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        switch pathComponents.first?.lowercased() {
        case "watch":
            return sanitizedYouTubeVideoID(
                queryItems?.first(where: { $0.name == "v" })?.value
            )
        case "embed", "shorts", "live":
            return sanitizedYouTubeVideoID(pathComponents.dropFirst().first)
        default:
            return sanitizedYouTubeVideoID(
                queryItems?.first(where: { $0.name == "v" })?.value
            )
        }
    }

    private static func sanitizedYouTubeVideoID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }

        return trimmed
    }
}
