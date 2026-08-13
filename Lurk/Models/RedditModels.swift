import CoreGraphics
import Foundation

// MARK: - API Response Types

nonisolated struct RedditListing: Decodable {
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
    let secureMedia: Media?
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
    let fallbackUrl: String?
    let hlsUrl: String?
    let width: Int?
    let height: Int?
    let isGif: Bool?
}

struct Preview: Decodable {
    let images: [PreviewImage]?
    let redditVideoPreview: RedditVideo?
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

    var decodedStaticUrl: String? {
        u?.replacingOccurrences(of: "&amp;", with: "&")
    }

    var decodedAnimatedUrl: String? {
        gif?.replacingOccurrences(of: "&amp;", with: "&")
    }

    var decodedUrl: String? {
        decodedStaticUrl ?? decodedAnimatedUrl
    }
}

struct GalleryMedia: Identifiable {
    let id: Int
    let url: URL
    let isAnimated: Bool
    let posterURL: URL?

    init(id: Int, url: URL, isAnimated: Bool, posterURL: URL? = nil) {
        self.id = id
        self.url = url
        self.isAnimated = isAnimated
        self.posterURL = posterURL
    }
}

enum AnimatedPostMedia: Equatable {
    case gif(URL)
    case video(URL)
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
        if let source = preview?.images?.first?.source,
           let url = URL(string: source.decodedUrl),
           url.isHTTPMediaURL {
            return url
        }
        if let firstItem = galleryData?.items?.first,
           let meta = mediaMetadata?[firstItem.mediaId],
           let urlString = meta.s?.decodedUrl,
           let url = URL(string: urlString),
           url.isHTTPMediaURL {
            return url
        }
        return nil
    }

    var animatedImageURL: URL? {
        if let directURL = decodedPostURL,
           directURL.isHTTPMediaURL,
           directURL.isGIFURL {
            return directURL
        }
        if let firstItem = galleryData?.items?.first,
           let meta = mediaMetadata?[firstItem.mediaId],
           meta.isAnimated,
           let urlString = meta.s?.decodedAnimatedUrl ?? meta.s?.decodedStaticUrl,
           let url = URL(string: urlString),
           url.isHTTPMediaURL,
           meta.s?.decodedAnimatedUrl != nil || url.isGIFURL {
            return url
        }
        guard let imageURL,
              imageURL.isHTTPMediaURL,
              imageURL.isGIFURL else { return nil }
        return imageURL
    }

    var imageAspectRatio: CGFloat? {
        if let source = preview?.images?.first?.source, source.height > 0 {
            return CGFloat(source.width) / CGFloat(source.height)
        }
        if let firstItem = galleryData?.items?.first,
           let source = mediaMetadata?[firstItem.mediaId]?.s,
           let width = source.x,
           let height = source.y,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return nil
    }

    var videoURL: URL? {
        playbackVideo?.playbackURL
    }

    var downloadableVideoURLs: [URL] {
        guard !isYouTubeVideo, let video = playbackVideo else { return [] }

        let candidates = [
            video.decodedHLSUrl,
            video.decodedFallbackUrl
        ]
        var seen = Set<String>()
        return candidates.compactMap { rawURL in
            guard let rawURL,
                  let url = URL(string: rawURL),
                  url.isHTTPMediaURL else { return nil }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    var downloadableVideoURL: URL? {
        downloadableVideoURLs.first
    }

    var videoAspectRatio: CGFloat? {
        if let video = playbackVideo,
           let width = video.width,
           let height = video.height,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return nil
    }

    var loopsVideo: Bool {
        playbackVideo?.isGif == true
    }

    var animatedMedia: AnimatedPostMedia? {
        if loopsVideo, let videoURL {
            return .video(videoURL)
        }
        if let animatedImageURL {
            return .gif(animatedImageURL)
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
            guard let meta = mediaMetadata?[item.mediaId] else { continue }
            let animatedURL = meta.s?.decodedAnimatedUrl
                .flatMap(URL.init(string:))
                .flatMap { $0.isHTTPMediaURL ? $0 : nil }
            let staticURL = meta.s?.decodedStaticUrl
                .flatMap(URL.init(string:))
                .flatMap { $0.isHTTPMediaURL ? $0 : nil }
            guard let url = meta.isAnimated
                ? (animatedURL ?? staticURL)
                : (staticURL ?? animatedURL) else { continue }
            let isAnimated = meta.isAnimated && (animatedURL != nil || url.isGIFURL)
            result.append(
                GalleryMedia(
                    id: result.count,
                    url: url,
                    isAnimated: isAnimated,
                    posterURL: staticURL
                )
            )
        }
        return result
    }

    var redditURL: URL {
        URL(string: "https://www.reddit.com\(permalink)")!
    }

    var externalLinkURL: URL? {
        guard !isSelf else { return nil }
        guard let candidate = URL(string: url.replacingOccurrences(of: "&amp;", with: "&")) else { return nil }
        guard let scheme = candidate.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = candidate.host?.lowercased() else { return nil }
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard normalizedHost != "reddit.com",
              !normalizedHost.hasSuffix(".reddit.com"),
              normalizedHost != "redd.it",
              !normalizedHost.hasSuffix(".redd.it") else { return nil }
        return candidate
    }

    var externalLinkDomain: String? {
        guard let host = externalLinkURL?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var matchesFilteredKeyword: Bool {
        Post.filteredKeywords.contains { title.range(of: $0, options: .caseInsensitive) != nil }
    }

    private var decodedPostURL: URL? {
        URL(string: url.replacingOccurrences(of: "&amp;", with: "&"))
    }

    private var playbackVideo: RedditVideo? {
        for video in [media?.redditVideo, secureMedia?.redditVideo].compactMap({ $0 }) {
            if (isVideo || video.isGif == true), video.playbackURL != nil {
                return video
            }
        }
        if let previewVideo = preview?.redditVideoPreview,
           previewVideo.isGif == true,
           previewVideo.playbackURL != nil {
            return previewVideo
        }
        return nil
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

private extension RedditVideo {
    var playbackURL: URL? {
        [decodedHLSUrl, decodedFallbackUrl]
            .compactMap { rawURL -> URL? in
                guard let rawURL,
                      let url = URL(string: rawURL),
                      url.isHTTPMediaURL else { return nil }
                return url
            }
            .first
    }

    var decodedFallbackUrl: String? {
        fallbackUrl?.replacingOccurrences(of: "&amp;", with: "&")
    }

    var decodedHLSUrl: String? {
        hlsUrl?.replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension URL {
    var isHTTPMediaURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var isGIFURL: Bool {
        pathExtension.caseInsensitiveCompare("gif") == .orderedSame
    }
}
