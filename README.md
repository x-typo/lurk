# Lurk

A lightweight Reddit client built with React Native and Expo, designed for distraction-free browsing.

## About

Lurk was developed as both a personal utility for ad-free Reddit browsing and a learning project to explore modern mobile development practices. The app demonstrates real-world implementation of OAuth authentication, REST API integration, and React Native best practices.

## Features

- **Home Feed** - View posts from subscribed subreddits
- **Popular Feed** - Browse trending content from r/popular
- **Profile** - Secure sign-in with Reddit to access personalized feeds
- **Swipe Gestures** - Swipe left to hide a post, swipe right to open in Safari
- **Dark Mode** - Native dark theme enabled by default
- **Pull-to-Refresh** - Refresh feeds across all screens

## Tech Stack

| Technology            | Purpose                                |
| --------------------- | -------------------------------------- |
| **React Native**      | Cross-platform mobile framework        |
| **Expo (~54.0)**      | Development toolchain and build system |
| **TypeScript**        | Type-safe development with strict mode |
| **Reddit OAuth2 API** | Data source for Reddit content         |
| **expo-auth-session** | OAuth 2.0 authentication               |
| **expo-secure-store** | Secure token storage                   |
| **expo-web-browser**  | Open posts in Safari                   |
| **React Navigation**  | Tab navigation                         |

## Learning Outcomes

This project provided hands-on experience with:

- **OAuth 2.0** - Implementing authorization flow for mobile apps
- **REST APIs** - Working with Reddit's API and rate limits (100 qpm)
- **React Native Patterns** - FlatList optimization, custom hooks, context providers
- **TypeScript** - Strict typing for API responses and component props
- **Gesture Handling** - Swipe actions for intuitive mobile UX
- **Mobile UX** - Pull-to-refresh, dark theme, minimal interface design

## Project Structure

```
src/
  api/           # Reddit API integration
  components/    # Reusable UI components
  constants/     # Colors, configuration
  context/       # Authentication context provider
  hooks/         # Custom hooks
  screens/       # Screen components
  types/         # TypeScript type definitions
```

## Setup

1. Clone the repository
2. Install dependencies:
   ```bash
   npm install
   ```
3. Create a `.env` file with Reddit API credentials:
   ```
   EXPO_PUBLIC_REDDIT_CLIENT_ID=your_client_id
   EXPO_PUBLIC_REDDIT_REDIRECT_URI=your_redirect_uri
   ```
4. Start the development server:
   ```bash
   npm start
   ```

### Reddit OAuth Configuration

To enable authenticated features:

1. Create an app at [Reddit App Preferences](https://www.reddit.com/prefs/apps)
2. Select "installed app" as the app type
3. Set the redirect URI based on your environment:
   - **Expo Go (development)**: `exp://[your-ip]:8081`
   - **Standalone build**: `lurk://`
4. Add the Client ID to your `.env` file

## Scripts

```bash
npm start        # Start Expo dev server
npm run ios      # Run on iOS simulator
npm run android  # Run on Android emulator
```

## Design Philosophy

The app intentionally limits functionality to basic browsing and two swipe actions. Any interaction beyond viewing or hiding posts opens the native browser, keeping the app lightweight and well within Reddit's API rate limits.

## Acknowledgments

- [Reddit](https://www.reddit.com) for providing the API
