# Lurk

A minimal, ad-free Reddit client built with SwiftUI. No accounts, no ads, no tracking.

## About

Lurk uses Reddit's anonymous `.json` endpoint to browse content without authentication. Zero dependencies, dark mode only, native SwiftUI on iOS 18+.

## Features

- **Home Feed** - Aggregated posts from followed subreddits
- **Popular Feed** - Trending content from r/popular with time filtering
- **Subreddit Management** - Follow/unfollow subreddits, browse individual feeds
- **Swipe Gestures** - Swipe left to hide a post, swipe right to open in Safari
- **Post Hiding** - Hidden posts persist across sessions (UserDefaults, capped at 5,000)
- **Dark Mode** - Native dark theme, no toggle
- **Pull-to-Refresh** - Refresh any feed

## Tech Stack

| Technology | Purpose |
| --- | --- |
| **SwiftUI** | UI framework (iOS 18+, Tab API) |
| **@Observable** | State management (Bankai pattern) |
| **Actor** | Thread-safe API client |
| **UserDefaults** | Local persistence for hidden posts and subreddit list |
| **Reddit .json API** | Anonymous endpoint, no auth required (100 QPM) |

## Architecture

```
Lurk/
  Constants/     # Theme (colors)
  Models/        # Reddit API response types, computed properties
  Services/      # RedditClient (actor), PostFilterStore, SubredditStore
  Utilities/     # Formatters (time, score)
  Views/         # SwiftUI views
    PaginatedFeedView   # Shared paginated feed component
    HomeFeedView        # Multi-subreddit aggregated feed
    PopularFeedView     # r/popular wrapper
    SubredditFeedView   # Single subreddit wrapper
    PostCardView        # Card with swipe gestures
    PostDetailView      # Full post sheet
    SubredditsView      # Subreddit picker and management
```

## Setup

1. Clone the repository
2. Open `Lurk/Lurk.xcodeproj` in Xcode 16+
3. Build and run on a simulator or device (iOS 18+)

### Deploy to Physical Device

```bash
xcodebuild -project Lurk/Lurk.xcodeproj -scheme Lurk \
  -destination 'id=DEVICE_UUID' -configuration Release
```

No signing configuration, dev server, or environment variables needed.

## Design Philosophy

Two interactions beyond reading: hide (swipe left) or open in Safari (swipe right). Everything else stays in the browser. This keeps the app lightweight, within Reddit's rate limits, and free of auth complexity.
