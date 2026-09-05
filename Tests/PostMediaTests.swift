import Foundation
import Testing
@testable import Lurk

@Suite("Post media routing")
struct PostMediaTests {
    @Test("External media fallback opens only web URLs")
    func externalMediaFallbackValidatesAndForwardsURL() {
        var openedURLs: [URL] = []
        let opener = ExternalMediaURLOpener { openedURLs.append($0) }
        let safeURL = URL(string: "https://media.example.com/oversized.gif")!

        #expect(opener.open(safeURL))
        #expect(!opener.open(URL(fileURLWithPath: "/private/tmp/oversized.gif")))
        #expect(!opener.open(URL(string: "data:image/gif;base64,R0lGODlh")!))
        #expect(openedURLs == [safeURL])
    }

    @Test("A direct GIF post prefers animation over its static preview")
    func resolvesDirectGIF() throws {
        let post = try makePost(
            url: "https://media.example.com/loop.GIF?source=reddit",
            preview: [
                "images": [[
                    "source": [
                        "url": "https://preview.example.com/poster.jpg",
                        "width": 640,
                        "height": 360,
                    ],
                ]],
            ]
        )

        #expect(post.imageURL == URL(string: "https://preview.example.com/poster.jpg"))
        #expect(post.animatedImageURL == URL(string: "https://media.example.com/loop.GIF?source=reddit"))
        #expect(post.animatedMedia == .gif(URL(string: "https://media.example.com/loop.GIF?source=reddit")!))
    }

    @Test("A Reddit GIF video preview is playable and loops")
    func resolvesRedditVideoPreviewGIF() throws {
        let post = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/fixture",
            preview: [
                "images": [[
                    "source": [
                        "url": "https://preview.example.com/poster.jpg",
                        "width": 720,
                        "height": 1280,
                    ],
                ]],
                "reddit_video_preview": [
                    "fallback_url": "https://v.redd.it/fixture/DASH_720.mp4?source=fallback&amp;v=1",
                    "hls_url": "https://v.redd.it/fixture/HLSPlaylist.m3u8?source=fallback&amp;v=1",
                    "width": 720,
                    "height": 1280,
                    "is_gif": true,
                ],
            ]
        )

        let expectedURL = URL(string: "https://v.redd.it/fixture/HLSPlaylist.m3u8?source=fallback&v=1")!
        #expect(post.videoURL == expectedURL)
        let videoAspectRatio = try #require(post.videoAspectRatio)
        #expect(abs(videoAspectRatio - (720.0 / 1280.0)) < 0.000_001)
        #expect(post.loopsVideo)
        #expect(post.animatedMedia == .video(expectedURL))
    }

    @Test("Animated gallery metadata keeps its GIF source separate from its poster")
    func resolvesAnimatedGalleryItem() throws {
        let post = try makePost(
            url: "https://www.reddit.com/gallery/fixture",
            galleryData: [
                "items": [["media_id": "animated-item"]],
            ],
            mediaMetadata: [
                "animated-item": [
                    "e": "AnimatedImage",
                    "s": [
                        "u": "https://preview.example.com/gallery-poster.jpg",
                        "gif": "https://i.redd.it/gallery-animation.gif",
                        "x": 800,
                        "y": 600,
                    ],
                ],
            ]
        )

        #expect(post.imageURL == URL(string: "https://preview.example.com/gallery-poster.jpg"))
        #expect(post.animatedImageURL == URL(string: "https://i.redd.it/gallery-animation.gif"))
        let imageAspectRatio = try #require(post.imageAspectRatio)
        #expect(abs(imageAspectRatio - (800.0 / 600.0)) < 0.000_001)
        #expect(post.galleryItems.first?.url == URL(string: "https://i.redd.it/gallery-animation.gif"))
        #expect(post.galleryItems.first?.isAnimated == true)
        #expect(post.galleryItems.first?.posterURL == URL(string: "https://preview.example.com/gallery-poster.jpg"))
    }

    @Test("Incomplete animated gallery metadata falls back to a static poster")
    func fallsBackIncompleteAnimatedGalleryItem() throws {
        let post = try makePost(
            url: "https://www.reddit.com/gallery/incomplete",
            galleryData: [
                "items": [["media_id": "incomplete-item"]],
            ],
            mediaMetadata: [
                "incomplete-item": [
                    "e": "AnimatedImage",
                    "s": [
                        "u": "https://preview.example.com/gallery-poster.jpg",
                        "x": 800,
                        "y": 600,
                    ],
                ],
            ]
        )

        #expect(post.animatedImageURL == nil)
        #expect(post.galleryItems.first?.url == URL(string: "https://preview.example.com/gallery-poster.jpg"))
        #expect(post.galleryItems.first?.isAnimated == false)
    }

    @Test("A normal Reddit video remains non-looping video")
    func preservesNormalRedditVideo() throws {
        let post = try makePost(
            url: "https://v.redd.it/regular",
            isVideo: true,
            media: [
                "reddit_video": [
                    "fallback_url": "https://v.redd.it/regular/DASH_720.mp4",
                    "width": 1280,
                    "height": 720,
                    "is_gif": false,
                ],
            ]
        )

        #expect(post.videoURL == URL(string: "https://v.redd.it/regular/DASH_720.mp4"))
        #expect(post.loopsVideo == false)
        #expect(post.animatedMedia == nil)
    }

    @Test("An incomplete primary video falls through to a playable GIF preview")
    func fallsThroughIncompletePrimaryVideo() throws {
        let post = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/fallback",
            isVideo: true,
            media: [
                "reddit_video": [
                    "width": 320,
                    "height": 180,
                    "is_gif": true,
                ],
            ],
            secureMedia: [
                "reddit_video": [
                    "fallback_url": "file:///private/tmp/not-playable.mp4",
                    "is_gif": true,
                ],
            ],
            preview: [
                "reddit_video_preview": [
                    "fallback_url": "https://v.redd.it/fallback/DASH_720.mp4",
                    "width": 720,
                    "height": 1280,
                    "is_gif": true,
                ],
            ]
        )

        let expectedURL = URL(string: "https://v.redd.it/fallback/DASH_720.mp4")!
        #expect(post.videoURL == expectedURL)
        let videoAspectRatio = try #require(post.videoAspectRatio)
        #expect(abs(videoAspectRatio - (720.0 / 1280.0)) < 0.000_001)
        #expect(post.loopsVideo)
        #expect(post.animatedMedia == .video(expectedURL))
    }

    @Test("Unsafe playback URLs are rejected")
    func rejectsUnsafePlaybackURLs() throws {
        let post = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/unsafe",
            isVideo: true,
            media: [
                "reddit_video": [
                    "fallback_url": "file:///private/tmp/not-media.mp4",
                    "is_gif": true,
                ],
            ]
        )

        #expect(post.videoURL == nil)
        #expect(post.downloadableVideoURLs.isEmpty)
        #expect(post.animatedMedia == nil)
    }

    @Test("Unsafe direct GIF URLs are rejected")
    func rejectsUnsafeGIFURLs() throws {
        let post = try makePost(url: "file:///private/tmp/not-media.gif")

        #expect(post.animatedImageURL == nil)
        #expect(post.animatedMedia == nil)
    }

    @Test("Static preview and gallery URLs accept HTTPS and reject unsafe schemes")
    func validatesStaticImageURLs() throws {
        let safePreview = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/safe-preview",
            preview: [
                "images": [[
                    "source": [
                        "url": "https://preview.example.com/poster.jpg",
                        "width": 640,
                        "height": 360,
                    ],
                ]],
            ]
        )
        let safeGallery = try makePost(
            url: "https://www.reddit.com/gallery/safe",
            galleryData: ["items": [["media_id": "safe-item"]]],
            mediaMetadata: [
                "safe-item": [
                    "e": "Image",
                    "s": ["u": "https://i.redd.it/safe-gallery.jpg"],
                ],
            ]
        )

        #expect(safePreview.imageURL == URL(string: "https://preview.example.com/poster.jpg"))
        #expect(safeGallery.imageURL == URL(string: "https://i.redd.it/safe-gallery.jpg"))

        for unsafeURL in ["file:///private/tmp/not-image.jpg", "data:image/jpeg;base64,AA==", "ftp://example.com/not-image.jpg"] {
            let preview = try makePost(
                url: "https://www.reddit.com/r/gifs/comments/unsafe-preview",
                preview: [
                    "images": [[
                        "source": [
                            "url": unsafeURL,
                            "width": 640,
                            "height": 360,
                        ],
                    ]],
                ]
            )
            let gallery = try makePost(
                url: "https://www.reddit.com/gallery/unsafe",
                galleryData: ["items": [["media_id": "unsafe-item"]]],
                mediaMetadata: [
                    "unsafe-item": [
                        "e": "Image",
                        "s": ["u": unsafeURL],
                    ],
                ]
            )

            #expect(preview.imageURL == nil)
            #expect(gallery.imageURL == nil)
        }
    }

    @Test("Secure Reddit media is used when ordinary media is absent")
    func resolvesSecureRedditMedia() throws {
        let post = try makePost(
            url: "https://v.redd.it/secure",
            isVideo: true,
            secureMedia: [
                "reddit_video": [
                    "fallback_url": "https://v.redd.it/secure/DASH_480.mp4",
                    "width": 480,
                    "height": 640,
                    "is_gif": true,
                ],
            ]
        )

        let expectedURL = URL(string: "https://v.redd.it/secure/DASH_480.mp4")!
        #expect(post.videoURL == expectedURL)
        #expect(post.loopsVideo)
        #expect(post.animatedMedia == .video(expectedURL))
    }

    @Test("Reddit MP4 preview variants play instead of decoding the original GIF")
    func prefersMP4VariantToRawGIF() throws {
        let post = try makePost(
            url: "https://i.redd.it/original.gif",
            preview: variantPreview(mp4URL: "https://preview.redd.it/loop.mp4?x=1&amp;y=2")
        )
        let videoURL = URL(string: "https://preview.redd.it/loop.mp4?x=1&y=2")!
        #expect(post.animatedMedia == .video(videoURL))
        #expect(post.videoURL == videoURL)
        #expect(post.loopsVideo)
        #expect(post.downloadableVideoURLs == [videoURL])
        #expect(post.videoAspectRatio == 0.5)
        #expect(post.imageURL?.absoluteString == "https://preview.redd.it/poster.jpg")
    }

    @Test("Ordinary Reddit HLS remains preferred over animation variants")
    func preservesOrdinaryVideoPriority() throws {
        let post = try makePost(
            url: "https://v.redd.it/original",
            isVideo: true,
            media: ["reddit_video": [
                "hls_url": "https://v.redd.it/original/HLSPlaylist.m3u8",
                "is_gif": false,
            ]],
            preview: variantPreview(mp4URL: "https://preview.redd.it/loop.mp4")
        )
        #expect(post.videoURL?.lastPathComponent == "HLSPlaylist.m3u8")
        #expect(!post.loopsVideo)
    }

    @Test("GIF variants remain animated when the outer URL has no GIF suffix")
    func resolvesGIFVariantWithoutDirectGIFURL() throws {
        let post = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/fixture/",
            preview: variantPreview(mp4URL: nil)
        )
        #expect(post.animatedMedia == .gif(URL(string: "https://preview.redd.it/loop.gif")!))
        #expect(post.imageURL?.lastPathComponent == "poster.jpg")
    }

    @Test("Unsafe and malformed MP4 variants fall back without losing the poster")
    func fallsBackFromInvalidMP4Variant() throws {
        for unsafeURL in ["file:///private/tmp/loop.mp4", "data:video/mp4;base64,AA"] {
            let post = try makePost(
                url: "https://www.reddit.com/r/gifs/comments/fixture/",
                preview: variantPreview(mp4URL: unsafeURL)
            )
            #expect(post.videoURL == nil)
            #expect(post.animatedImageURL?.lastPathComponent == "loop.gif")
            #expect(post.imageURL?.lastPathComponent == "poster.jpg")
        }
        let malformed = try makePost(
            url: "https://www.reddit.com/r/gifs/comments/fixture/",
            preview: ["images": [[
                "source": ["url": "https://preview.redd.it/poster.jpg", "width": 300, "height": 600],
                "variants": ["mp4": "bad", "gif": ["source": ["url": "https://preview.redd.it/loop.gif", "width": 300, "height": 600]]],
            ]]]
        )
        #expect(malformed.videoURL == nil)
        #expect(malformed.animatedImageURL?.lastPathComponent == "loop.gif")
        #expect(malformed.imageURL?.lastPathComponent == "poster.jpg")
    }

    private func variantPreview(mp4URL: String?) -> [String: Any] {
        var variants: [String: Any] = [
            "gif": ["source": ["url": "https://preview.redd.it/loop.gif", "width": 300, "height": 600]],
        ]
        if let mp4URL {
            variants["mp4"] = ["source": ["url": mp4URL, "width": 300, "height": 600]]
        }
        return ["images": [[
            "source": ["url": "https://preview.redd.it/poster.jpg", "width": 300, "height": 600],
            "variants": variants,
        ]]]
    }

    private func makePost(
        url: String,
        isVideo: Bool = false,
        media: [String: Any]? = nil,
        secureMedia: [String: Any]? = nil,
        preview: [String: Any]? = nil,
        galleryData: [String: Any]? = nil,
        mediaMetadata: [String: Any]? = nil
    ) throws -> Post {
        var payload: [String: Any] = [
            "id": "fixture",
            "title": "Animated fixture",
            "author": "reader",
            "subreddit": "gifs",
            "subreddit_name_prefixed": "r/gifs",
            "score": 1,
            "num_comments": 0,
            "created_utc": 1_700_000_000,
            "permalink": "/r/gifs/comments/fixture/animated_fixture/",
            "url": url,
            "selftext": "",
            "is_self": false,
            "is_video": isVideo,
            "stickied": false,
            "over_18": false,
        ]
        payload["media"] = media
        payload["secure_media"] = secureMedia
        payload["preview"] = preview
        payload["gallery_data"] = galleryData
        payload["media_metadata"] = mediaMetadata

        let data = try JSONSerialization.data(withJSONObject: payload)
        return try RedditAPI.decoder.decode(Post.self, from: data)
    }
}
