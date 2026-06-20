# Lurk

A personal, ad-free Reddit client built with SwiftUI. Dark, fast, and tuned for one person's reading workflow.

## About

Lurk uses Reddit's web session cookies for a personal signed-in browsing workflow. It is intended for local personal use only, not App Store distribution or public replacement of Reddit's official app.

## Features

- **Home Feed** - Front-page top posts for the day
- **Popular Feed** - r/popular top posts for the day
- **Subreddit Management** - Follow/unfollow subreddits, browse individual feeds
- **Swipe Gestures** - Swipe left to hide a post, swipe right to open in Safari
- **Post Hiding** - Hidden posts persist across sessions (UserDefaults, capped at 5,000)
- **Dark Mode** - Native dark theme, no toggle
- **Pull-to-Refresh** - Refresh any feed
- **Optional Account Actions** - Sign in to vote, comment, sync subscribed subreddits, and manage saved/hidden posts

## Tech Stack

| Technology | Purpose |
| --- | --- |
| **SwiftUI** | UI framework (iOS 18+, Tab API) |
| **@Observable** | State management (Bankai pattern) |
| **Actor** | Thread-safe API client |
| **UserDefaults** | Local persistence for hidden posts and subreddit list |
| **Reddit Web/API Endpoints** | Personal session-backed reads and account actions |

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
2. Open `Lurk.xcodeproj` in Xcode 26+
3. Build and run on a simulator or device (iOS 18+)
4. Sign in from the app's Settings tab using the embedded Reddit web login

### Deploy to Physical Device

```bash
scripts/deploy-phone.sh
```

If CoreDevice gets stuck during install, retry with `scripts/deploy-phone.sh --restart-coredevice`.
For the fastest path, put your phone UDID in ignored local config at `.env.local`:

```bash
printf 'DEVICE_ID=DEVICE_UUID\n' > .env.local
```

No Reddit app client ID, server, or client secret is needed.

## Design Philosophy

Reading stays native and low-distraction. Account actions are available only after your personal Reddit web sign-in.
