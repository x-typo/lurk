# Copilot Code Review Instructions

This is a minimal iOS Reddit client built with SwiftUI. Zero external dependencies.
Flag violations of these conventions during review.

## Zero Dependencies

- No third-party packages. Apple frameworks only (Foundation, SwiftUI, AVKit, WebKit, Photos, UIKit, ImageIO, CoreGraphics as needed).
- No SPM dependencies, no CocoaPods, no Carthage. Flag any `Package.swift` or `Podfile` additions.
- `URLSession` for networking. No Alamofire, no custom HTTP libraries.
- `AsyncImage` for remote images. No image caching frameworks.
- This is a hard constraint, not a preference.

## Architecture

- **Stores + Views**: `@Observable` stores manage state, views render it.
- `RedditClient` is an actor for thread-safe API calls. Flag if changed to a class.
- `RedditSession` manages cookie/auth state. `PostFilterStore` manages hidden posts. `SubredditStore` manages subreddit list.
- Views receive stores as parameters or via `@Environment`. Not `@EnvironmentObject`.
- Computed properties on models for display logic (`Post` extensions). No formatting in views.

## Concurrency

- Actor isolation on `RedditClient`. All API methods are async.
- `@MainActor` on observable stores that drive UI.
- `@Observable` for all stores. Not `ObservableObject`.
- Async errors on non-critical paths (pagination, post hiding) use `try?` for silent failure.
- Critical paths (initial feed load, auth) use `try` with user-facing error display.

## Theming

- All colors from `Theme` enum in `Constants/Theme.swift`. No hardcoded color literals or hex values.
- Dark theme only. No light mode. Flag `colorScheme` conditionals or light-mode colors.
- Status colors and UI accents defined centrally. Flag any `Color(red:green:blue:)` outside Theme.

## Formatting

- All display formatting through `Formatters` enum (`timeAgo()`, score formatting).
- No inline date or number formatting in views. Flag `DateFormatter` or `NumberFormatter` usage in view code. Simple string interpolation of preformatted values from `Formatters` is fine.

## Gesture Handling

- Swipe gestures use `DragGesture` with axis locking to prevent conflict with `ScrollView` scrolling.
- Axis lock pattern: determine axis on first movement (`abs(dx) > abs(dy)`), then lock. Flag gestures without axis detection.
- Swipe left: hide post. Swipe right: open in Safari.
- Two gestures only. Do not add new gesture actions without updating this document.

## UserDefaults & Persistence

- Storage keys as `private static let` constants on the store class. Flag string literals used as keys.
- Hidden post IDs capped at 5000 entries (`maxEntries`). Flag unbounded collection growth.
- Subreddit list persisted in UserDefaults. Flag any persistence mechanism other than UserDefaults (no CoreData, no SwiftData, no files).
- No sensitive data in UserDefaults. Auth tokens go through `RedditSession` only.

## Reddit API

- Anonymous `.json` endpoint for unauthenticated browsing. Rate limit: 100 requests/minute.
- `after` parameter for pagination. Flag any offset-based pagination.
- Video playback uses `RedditVideo.fallbackUrl` (video-only stream). Flag assumptions that `Post.url` is directly playable for video posts.
- Comment trees are recursive. `maxRenderDepth` limits rendering depth. Flag unbounded recursion.

## Error Handling

- Graceful fallback to `localizedDescription` for unexpected errors in UI.
- Pagination errors do not block the feed. Flag any error that clears existing loaded content.
- `URLError` checks for `.badURL` and `.badServerResponse`. Flag generic catch-all without specific handling.
- No force unwraps in normal control flow. Force unwraps are acceptable for static, guaranteed-valid constants (e.g., `URL(string: "https://...")!`) and compile-time patterns (`try! NSRegularExpression`). Use `guard let`/`if let` for runtime values.

## SwiftUI Patterns

- `TabView` (iOS 18 Tab API) for top-level navigation. Per-tab content.
- `LazyVStack` for feed lists. Not `VStack` with `ForEach`.
- `PaginatedFeedView` is the reusable pagination component. New feeds should use it, not reimplement pagination.
- Pull-to-refresh on all feed views.
- Sheet presentation for post detail + comments.

## Testing

- No test suite currently. When adding tests:
  - Swift Testing framework for new tests.
  - Priority targets: `Formatters`, `RedditModels` computed properties, `PostFilterStore` logic.
  - Actor-isolated `RedditClient` testable via dependency injection.
  - Mock `URLSession` via `URLProtocol` subclass, not by making the client a protocol.

## Naming

- Types: PascalCase. Views end with `View`, stores with `Store` or `Client` or `Session`.
- Functions/properties: camelCase.
- File names match the primary type.
- Avoid redundant comments that restate code. `// MARK:` section labels and constraint/rationale comments are fine.
