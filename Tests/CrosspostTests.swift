import Foundation
import Testing
@testable import Lurk

@Suite("Crosspost content")
struct CrosspostTests {
    @Test("Original video supplies media while the crosspost keeps its identity")
    func resolvesOriginalVideoWithoutChangingIdentity() throws {
        let post = try decode(parent: [
            "title": "Original title", "author": "original_author", "subreddit": "original",
            "id": "original_id", "permalink": "/r/original/comments/original_id/title/",
            "url": "https://v.redd.it/original", "is_video": true,
            "secure_media": ["reddit_video": [
                "hls_url": "https://v.redd.it/original/HLSPlaylist.m3u8?x=1&amp;y=2",
                "fallback_url": "https://v.redd.it/original/DASH_720.mp4",
                "width": 720, "height": 1280, "is_gif": false,
            ]],
        ])

        #expect(post.id == "outer_id")
        #expect(post.title == "Outer title")
        #expect(post.author == "outer_author")
        #expect(post.subreddit == "outer")
        #expect(post.score == 17)
        #expect(post.numComments == 9)
        #expect(post.selftext == "Outer commentary")
        #expect(post.redditURL.absoluteString == "https://www.reddit.com/r/outer/comments/outer_id/title/")
        #expect(post.crosspost?.originalURL?.absoluteString == "https://www.reddit.com/r/original/comments/original_id/title/")
        #expect(post.crosspost?.subredditNamePrefixed == "r/original")
        #expect(!post.isVideo)
        #expect(post.effectiveIsVideo)
        #expect(!post.loopsVideo)
        #expect(post.videoURL?.absoluteString == "https://v.redd.it/original/HLSPlaylist.m3u8?x=1&y=2")
        #expect(post.downloadableVideoURLs.map(\.lastPathComponent) == ["HLSPlaylist.m3u8", "DASH_720.mp4"])
        let aspectRatio = try #require(post.videoAspectRatio)
        #expect(abs(aspectRatio - (720.0 / 1280.0)) < 0.000_001)
    }

    @Test("Original gallery preserves order, animation, poster, and dimensions")
    func resolvesOriginalGallery() throws {
        let post = try decode(parent: [
            "url": "https://www.reddit.com/gallery/original_id",
            "gallery_data": ["items": [["media_id": "second"], ["media_id": "first"]]],
            "media_metadata": [
                "first": ["e": "Image", "s": ["u": "https://i.redd.it/first.jpg", "x": 640, "y": 480]],
                "second": ["e": "AnimatedImage", "s": [
                    "u": "https://preview.redd.it/second.jpg", "gif": "https://i.redd.it/second.gif",
                    "x": 300, "y": 600,
                ]],
            ],
        ])
        #expect(post.isGallery)
        #expect(post.galleryItems.map(\.url.lastPathComponent) == ["second.gif", "first.jpg"])
        #expect(post.galleryItems.first?.posterURL?.lastPathComponent == "second.jpg")
        #expect(post.galleryItems.first?.isAnimated == true)
        #expect(post.imageURL?.lastPathComponent == "second.jpg")
        #expect(post.animatedImageURL?.lastPathComponent == "second.gif")
        #expect(post.imageAspectRatio == 0.5)
    }

    @Test("Original text, direct image, GIF, YouTube, and external link resolve independently")
    func resolvesOriginalContentKinds() throws {
        let text = try decode(parent: ["selftext": "Original body", "is_self": true])
        #expect(text.crosspostBody == "Original body")
        #expect(text.selftext == "Outer commentary")
        #expect(text.externalLinkURL == nil)

        let image = try decode(parent: ["url": "https://i.redd.it/original.jpg"])
        #expect(image.imageURL?.absoluteString == "https://i.redd.it/original.jpg")
        let gif = try decode(parent: ["url": "https://i.redd.it/original.gif"])
        #expect(gif.animatedMedia == .gif(URL(string: "https://i.redd.it/original.gif")!))
        let youtube = try decode(parent: ["url": "https://youtu.be/abc123", "is_self": false])
        #expect(youtube.youtubeVideoID == "abc123")
        #expect(youtube.downloadableVideoURLs.isEmpty)
        let article = try decode(parent: ["url": "https://example.com/article?x=1&amp;y=2", "is_self": false])
        #expect(article.externalLinkURL?.absoluteString == "https://example.com/article?x=1&y=2")
        #expect(article.externalLinkDomain == "example.com")
        #expect(article.imageURL == nil)
    }

    @Test("Original animation uses its MP4 variant and retains the original poster")
    func resolvesOriginalMP4Variant() throws {
        let post = try decode(parent: [
            "url": "https://i.redd.it/original.gif",
            "preview": ["images": [[
                "source": ["url": "https://preview.redd.it/original.jpg", "width": 400, "height": 200],
                "variants": ["mp4": ["source": [
                    "url": "https://preview.redd.it/original.mp4", "width": 400, "height": 200,
                ]]],
            ]]],
        ])
        #expect(post.animatedMedia == .video(URL(string: "https://preview.redd.it/original.mp4")!))
        #expect(post.imageURL?.lastPathComponent == "original.jpg")
        #expect(post.videoAspectRatio == 2)
        #expect(post.id == "outer_id")
    }

    @Test("Original secure video cannot borrow the outer primary video or preview")
    func keepsOriginalSecureVideoCoherent() throws {
        let post = try decode(parent: [
            "is_video": true,
            "secure_media": ["reddit_video": [
                "hls_url": "https://v.redd.it/original/HLSPlaylist.m3u8",
                "fallback_url": "https://v.redd.it/original/DASH_720.mp4",
                "width": 720, "height": 1280, "is_gif": false,
            ]],
        ], outer: [
            "is_video": true,
            "media": ["reddit_video": [
                "hls_url": "https://v.redd.it/outer/HLSPlaylist.m3u8",
                "width": 1920, "height": 1080, "is_gif": false,
            ]],
            "preview": ["images": [["source": [
                "url": "https://preview.redd.it/outer.jpg", "width": 1920, "height": 1080,
            ]]]],
        ])
        #expect(post.videoURL?.absoluteString == "https://v.redd.it/original/HLSPlaylist.m3u8")
        #expect(post.downloadableVideoURLs.map(\.absoluteString) == [
            "https://v.redd.it/original/HLSPlaylist.m3u8", "https://v.redd.it/original/DASH_720.mp4",
        ])
        let aspectRatio = try #require(post.videoAspectRatio)
        #expect(abs(aspectRatio - (720.0 / 1280.0)) < 0.000_001)
        #expect(!post.loopsVideo)
        #expect(post.imageURL == nil)
        #expect(post.imageAspectRatio == nil)
    }

    @Test("An original direct GIF cannot inherit an outer MP4 preview")
    func keepsOriginalGIFCoherent() throws {
        let post = try decode(parent: ["url": "https://i.redd.it/original.gif"], outer: [
            "preview": ["images": [[
                "source": ["url": "https://preview.redd.it/outer.jpg", "width": 300, "height": 600],
                "variants": ["mp4": ["source": [
                    "url": "https://preview.redd.it/outer.mp4", "width": 300, "height": 600,
                ]]],
            ]]],
        ])
        #expect(post.animatedMedia == .gif(URL(string: "https://i.redd.it/original.gif")!))
        #expect(post.imageURL?.absoluteString == "https://i.redd.it/original.gif")
        #expect(post.videoURL == nil)
        #expect(post.videoAspectRatio == nil)
        #expect(post.imageAspectRatio == nil)
        #expect(post.downloadableVideoURLs.isEmpty)
    }

    @Test("Original gallery dimensions and poster stay together despite an outer preview")
    func keepsOriginalGalleryCoherent() throws {
        let post = try decode(parent: [
            "gallery_data": ["items": [["media_id": "original"]]],
            "media_metadata": ["original": ["e": "Image", "s": [
                "u": "https://i.redd.it/original.jpg", "x": 300, "y": 600,
            ]]],
        ], outer: [
            "preview": ["images": [["source": [
                "url": "https://preview.redd.it/outer.jpg", "width": 1920, "height": 1080,
            ]]]],
        ])
        #expect(post.imageURL?.lastPathComponent == "original.jpg")
        #expect(post.imageAspectRatio == 0.5)
        #expect(post.galleryItems.map(\.url.lastPathComponent) == ["original.jpg"])
    }

    @Test("An unusable original falls back to the complete outer media source")
    func fallsBackAsAWholeWhenOriginalHasNoContent() throws {
        for originalURL in ["", "not a URL", "file:///private/tmp/invalid.gif", "https://www.reddit.com/r/original/comments/deleted/title/"] {
            let post = try decode(parent: [
                "title": "Unavailable original", "url": originalURL, "selftext": "[removed]",
                "is_video": false, "media": "invalid",
                "gallery_data": ["items": [["media_id": "missing"]]],
            ], outer: [
                "is_video": true,
                "media": ["reddit_video": [
                    "hls_url": "https://v.redd.it/outer/HLSPlaylist.m3u8",
                    "fallback_url": "https://v.redd.it/outer/DASH_720.mp4",
                    "width": 1600, "height": 800, "is_gif": false,
                ]],
                "preview": ["images": [["source": [
                    "url": "https://preview.redd.it/outer.jpg", "width": 1600, "height": 800,
                ]]]],
            ])
            #expect(post.crosspost?.title == "Unavailable original")
            #expect(post.effectiveIsVideo)
            #expect(post.videoURL?.absoluteString == "https://v.redd.it/outer/HLSPlaylist.m3u8")
            #expect(post.downloadableVideoURLs.map(\.absoluteString) == [
                "https://v.redd.it/outer/HLSPlaylist.m3u8", "https://v.redd.it/outer/DASH_720.mp4",
            ])
            #expect(post.videoAspectRatio == 2)
            #expect(post.imageURL?.lastPathComponent == "outer.jpg")
            #expect(post.imageAspectRatio == 2)
            #expect(post.galleryItems.isEmpty)
        }
    }

    @Test("Missing, malformed, and partial originals never discard the outer listing item")
    func toleratesUnavailableOriginals() throws {
        let parentLists: [Any] = [NSNull(), "malformed", [], [NSNull()], [42], [["title": "[deleted]", "media": "bad"]]]
        for parentList in parentLists {
            var payload = outerPayload
            payload["crosspost_parent_list"] = parentList
            let data = try JSONSerialization.data(withJSONObject: ["data": ["children": [["data": payload]]]])
            let listing = try RedditAPI.decoder.decode(RedditListing.self, from: data)
            #expect(listing.data.children.first?.data.id == "outer_id")
        }
        let partial = try decode(parent: ["title": "[deleted]", "selftext": "[removed]", "media": "bad"])
        #expect(partial.crosspost?.title == "[deleted]")
        #expect(partial.crosspostBody == "[removed]")
        #expect(partial.videoURL == nil)
    }

    @Test("Nested originals are ignored and cannot replace the immediate original")
    func boundsOriginalDecoding() throws {
        let post = try decode(parent: [
            "title": "Immediate original", "selftext": "Immediate body",
            "crosspost_parent_list": [[
                "title": "Nested original", "selftext": "Nested body", "url": "https://i.redd.it/nested.gif",
            ]],
        ])
        #expect(post.crosspost?.title == "Immediate original")
        #expect(post.crosspostBody == "Immediate body")
        #expect(post.animatedMedia == nil)
    }

    @Test("Original media and source links retain URL safety checks")
    func rejectsUnsafeOriginalURLs() throws {
        let post = try decode(parent: [
            "url": "file:///private/tmp/original.gif", "is_video": true,
            "permalink": "//example.com/not-reddit",
            "media": ["reddit_video": ["fallback_url": "file:///private/tmp/original.mp4"]],
            "preview": ["images": [["source": ["url": "data:image/png;base64,AA", "width": 1, "height": 1]]]],
        ])
        #expect(post.crosspost?.originalURL == nil)
        #expect(post.imageURL == nil)
        #expect(post.animatedImageURL == nil)
        #expect(post.videoURL == nil)
        #expect(post.downloadableVideoURLs.isEmpty)
        #expect(post.externalLinkURL == nil)
    }

    private var outerPayload: [String: Any] {
        [
            "id": "outer_id", "title": "Outer title", "author": "outer_author",
            "subreddit": "outer", "subreddit_name_prefixed": "r/outer", "score": 17,
            "num_comments": 9, "created_utc": 1_700_000_000,
            "permalink": "/r/outer/comments/outer_id/title/", "url": "https://www.reddit.com/r/original/comments/original_id/title/",
            "selftext": "Outer commentary", "is_self": false, "is_video": false,
            "stickied": false, "over_18": false,
        ]
    }

    private func decode(parent: [String: Any], outer: [String: Any] = [:]) throws -> Post {
        var payload = outerPayload.merging(outer) { _, replacement in replacement }
        payload["crosspost_parent_list"] = [parent]
        return try RedditAPI.decoder.decode(Post.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
