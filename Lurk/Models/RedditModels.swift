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
    var crosspost: CrosspostContent? = nil

    static let filteredKeywords: Set<String> = [
        "Artemis"
    ]
}

extension Post {
    private enum CodingKeys: String, CodingKey {
        case id, title, author, subreddit, subredditNamePrefixed, score, numComments
        case createdUtc, permalink, url, selftext, isSelf, isVideo, stickied, over18
        case postHint, media, secureMedia, preview, galleryData, mediaMetadata, crosspostParentList
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        author = try values.decode(String.self, forKey: .author)
        subreddit = try values.decode(String.self, forKey: .subreddit)
        subredditNamePrefixed = try values.decode(String.self, forKey: .subredditNamePrefixed)
        score = try values.decode(Int.self, forKey: .score)
        numComments = try values.decode(Int.self, forKey: .numComments)
        createdUtc = try values.decode(TimeInterval.self, forKey: .createdUtc)
        permalink = try values.decode(String.self, forKey: .permalink)
        url = try values.decode(String.self, forKey: .url)
        selftext = try values.decode(String.self, forKey: .selftext)
        isSelf = try values.decode(Bool.self, forKey: .isSelf)
        isVideo = try values.decode(Bool.self, forKey: .isVideo)
        stickied = try values.decode(Bool.self, forKey: .stickied)
        over18 = try values.decode(Bool.self, forKey: .over18)
        postHint = try values.decodeIfPresent(String.self, forKey: .postHint)
        media = try values.decodeIfPresent(Media.self, forKey: .media)
        secureMedia = try values.decodeIfPresent(Media.self, forKey: .secureMedia)
        preview = try values.decodeIfPresent(Preview.self, forKey: .preview)
        galleryData = try values.decodeIfPresent(GalleryData.self, forKey: .galleryData)
        mediaMetadata = try values.decodeIfPresent([String: MediaMetadataItem].self, forKey: .mediaMetadata)
        if var parents = try? values.nestedUnkeyedContainer(forKey: .crosspostParentList),
           !parents.isAtEnd,
           let parentDecoder = try? parents.superDecoder() {
            crosspost = try? CrosspostContent(from: parentDecoder)
        }
    }
}

// Only the immediate original contributes content; nested crossposts are not decoded.
struct CrosspostContent: Decodable {
    let title: String?
    let author: String?
    let subreddit: String?
    let permalink: String?
    let url: String?
    let selftext: String?
    let isSelf: Bool?
    let isVideo: Bool?
    let media: Media?
    let secureMedia: Media?
    let preview: Preview?
    let galleryData: GalleryData?
    let mediaMetadata: [String: MediaMetadataItem]?

    private enum CodingKeys: String, CodingKey {
        case title, author, subreddit, permalink, url, selftext, isSelf, isVideo
        case media, secureMedia, preview, galleryData, mediaMetadata
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try? values.decode(String.self, forKey: .title)
        author = try? values.decode(String.self, forKey: .author)
        subreddit = try? values.decode(String.self, forKey: .subreddit)
        permalink = try? values.decode(String.self, forKey: .permalink)
        url = try? values.decode(String.self, forKey: .url)
        selftext = try? values.decode(String.self, forKey: .selftext)
        isSelf = try? values.decode(Bool.self, forKey: .isSelf)
        isVideo = try? values.decode(Bool.self, forKey: .isVideo)
        media = try? values.decode(Media.self, forKey: .media)
        secureMedia = try? values.decode(Media.self, forKey: .secureMedia)
        preview = try? values.decode(Preview.self, forKey: .preview)
        galleryData = try? values.decode(GalleryData.self, forKey: .galleryData)
        mediaMetadata = try? values.decode([String: MediaMetadataItem].self, forKey: .mediaMetadata)
    }

    fileprivate var hasUsableContent: Bool {
        for video in [media?.redditVideo, secureMedia?.redditVideo].compactMap({ $0 }) {
            if (isVideo == true || video.isGif == true), video.playbackURL != nil { return true }
        }
        if let video = preview?.redditVideoPreview, video.isGif == true, video.playbackURL != nil {
            return true
        }
        if let image = preview?.images?.first {
            let sources = [image.source, image.variants?.gif?.source, image.variants?.mp4?.source]
            if sources.compactMap({ $0 }).contains(where: { Self.isUsableURL($0.decodedUrl) }) { return true }
        }
        if galleryData?.items?.contains(where: { item in
            guard let source = mediaMetadata?[item.mediaId]?.s else { return false }
            return [source.decodedStaticUrl, source.decodedAnimatedUrl]
                .compactMap { $0 }.contains(where: { Self.isUsableURL($0) })
        }) == true { return true }
        if let body = selftext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !body.isEmpty, body != "[removed]", body != "[deleted]" { return true }
        guard let rawURL = url?.replacingOccurrences(of: "&amp;", with: "&"),
              Self.isUsableURL(rawURL), let candidate = URL(string: rawURL),
              let host = candidate.host?.lowercased() else { return false }
        if ["jpg", "jpeg", "png", "webp", "gif"].contains(candidate.pathExtension.lowercased()) { return true }
        // A Reddit permalink without embedded content is an attribution link, not media.
        return host != "reddit.com" && !host.hasSuffix(".reddit.com")
            && host != "redd.it" && !host.hasSuffix(".redd.it")
    }

    private static func isUsableURL(_ rawURL: String) -> Bool {
        guard let candidate = URL(string: rawURL), candidate.host != nil else { return false }
        return candidate.isHTTPMediaURL
    }

    var subredditNamePrefixed: String? {
        subreddit.map { "r/\($0)" }
    }

    var originalURL: URL? {
        guard let permalink, permalink.hasPrefix("/"), !permalink.hasPrefix("//") else { return nil }
        return URL(string: "https://www.reddit.com\(permalink)")
    }
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
    var variants: PreviewVariants? = nil
}

extension PreviewImage {
    private enum CodingKeys: String, CodingKey { case source, variants }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(ImageSource.self, forKey: .source)
        variants = try? values.decode(PreviewVariants.self, forKey: .variants)
    }
}

struct PreviewVariants: Decodable {
    let gif: PreviewVariant?
    let mp4: PreviewVariant?

    private enum CodingKeys: String, CodingKey { case gif, mp4 }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gif = try? values.decode(PreviewVariant.self, forKey: .gif)
        mp4 = try? values.decode(PreviewVariant.self, forKey: .mp4)
    }
}

struct PreviewVariant: Decodable {
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
    var crosspostBody: String { crosspost?.selftext ?? "" }
    var effectiveIsVideo: Bool {
        guard let original = contentOriginal else { return isVideo }
        return original.isVideo ?? false
    }

    // Keep media and metadata from the same source; missing original fields stay absent.
    private var contentOriginal: CrosspostContent? {
        guard let crosspost, crosspost.hasUsableContent else { return nil }
        return crosspost
    }

    private var contentURL: String {
        guard let original = contentOriginal else { return url }
        return original.url ?? ""
    }
    private var contentIsSelf: Bool {
        guard let original = contentOriginal else { return isSelf }
        return original.isSelf ?? false
    }
    private var contentPreview: Preview? {
        guard let original = contentOriginal else { return preview }
        return original.preview
    }
    private var contentMedia: Media? {
        guard let original = contentOriginal else { return media }
        return original.media
    }
    private var contentSecureMedia: Media? {
        guard let original = contentOriginal else { return secureMedia }
        return original.secureMedia
    }
    private var contentGalleryData: GalleryData? {
        guard let original = contentOriginal else { return galleryData }
        return original.galleryData
    }
    private var contentMediaMetadata: [String: MediaMetadataItem]? {
        guard let original = contentOriginal else { return mediaMetadata }
        return original.mediaMetadata
    }

    var youtubeVideoID: String? {
        guard let parsedURL = URL(string: contentURL) else { return nil }
        return Self.youtubeVideoID(from: parsedURL)
    }

    var isYouTubeVideo: Bool {
        youtubeVideoID != nil
    }

    var imageURL: URL? {
        if let source = contentPreview?.images?.first?.source,
           let url = URL(string: source.decodedUrl),
           url.isHTTPMediaURL {
            return url
        }
        if let firstItem = contentGalleryData?.items?.first,
           let meta = contentMediaMetadata?[firstItem.mediaId],
           let urlString = meta.s?.decodedUrl,
           let url = URL(string: urlString),
           url.isHTTPMediaURL {
            return url
        }
        if let directURL = decodedPostURL,
           directURL.isHTTPMediaURL,
           ["jpg", "jpeg", "png", "webp", "gif"].contains(directURL.pathExtension.lowercased()) {
            return directURL
        }
        return nil
    }

    var animatedImageURL: URL? {
        if let directURL = decodedPostURL,
           directURL.isHTTPMediaURL,
           directURL.isGIFURL {
            return directURL
        }
        if let firstItem = contentGalleryData?.items?.first,
           let meta = contentMediaMetadata?[firstItem.mediaId],
           meta.isAnimated,
           let urlString = meta.s?.decodedAnimatedUrl ?? meta.s?.decodedStaticUrl,
           let url = URL(string: urlString),
           url.isHTTPMediaURL,
           meta.s?.decodedAnimatedUrl != nil || url.isGIFURL {
            return url
        }
        if let source = contentPreview?.images?.first?.variants?.gif?.source,
           let variantURL = URL(string: source.decodedUrl),
           variantURL.isHTTPMediaURL {
            return variantURL
        }
        guard let imageURL,
              imageURL.isHTTPMediaURL,
              imageURL.isGIFURL else { return nil }
        return imageURL
    }

    var imageAspectRatio: CGFloat? {
        if let source = contentPreview?.images?.first?.source, source.height > 0 {
            return CGFloat(source.width) / CGFloat(source.height)
        }
        if let firstItem = contentGalleryData?.items?.first,
           let source = contentMediaMetadata?[firstItem.mediaId]?.s,
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
        contentGalleryData?.items?.count ?? 0
    }

    var galleryItems: [GalleryMedia] {
        guard let items = contentGalleryData?.items else { return [] }
        var result: [GalleryMedia] = []
        for item in items {
            guard let meta = contentMediaMetadata?[item.mediaId] else { continue }
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
        guard !contentIsSelf else { return nil }
        guard let candidate = URL(string: contentURL.replacingOccurrences(of: "&amp;", with: "&")) else { return nil }
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
        URL(string: contentURL.replacingOccurrences(of: "&amp;", with: "&"))
    }

    private var playbackVideo: RedditVideo? {
        for video in [contentMedia?.redditVideo, contentSecureMedia?.redditVideo].compactMap({ $0 }) {
            if (effectiveIsVideo || video.isGif == true), video.playbackURL != nil {
                return video
            }
        }
        if let previewVideo = contentPreview?.redditVideoPreview,
           previewVideo.isGif == true,
           previewVideo.playbackURL != nil {
            return previewVideo
        }
        if let source = contentPreview?.images?.first?.variants?.mp4?.source,
           let variantURL = URL(string: source.decodedUrl),
           variantURL.isHTTPMediaURL {
            return RedditVideo(
                fallbackUrl: variantURL.absoluteString,
                hlsUrl: nil,
                width: source.width,
                height: source.height,
                isGif: true
            )
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
