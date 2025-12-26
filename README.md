# Lurk

A lightweight Reddit client built with React Native and Expo, designed for distraction-free browsing.

## Overview

Lurk provides a minimal interface for viewing Reddit content without ads or clutter. The app focuses on quick consumption of posts from the Home feed (subscribed subreddits) and the Popular feed, with simple swipe gestures for common actions.

## Features

- **Home Feed** — View posts from subscribed subreddits
- **Popular Feed** — Browse trending content from r/popular
- **Profile** — Authenticate with a Reddit account
- **Swipe Gestures** — Swipe left to hide a post, swipe right to open in Safari
- **Dark Mode** — Native dark theme for comfortable viewing

## Tech Stack

- React Native with Expo
- TypeScript
- Reddit OAuth2 API

## Project Structure

```
src/
  api/           # Reddit API integration
  components/    # Reusable UI components
  constants/     # App-wide constants (colors, etc.)
  context/       # Authentication context
  hooks/         # Custom React hooks
  screens/       # Screen components
  types/         # TypeScript type definitions
```

## Getting Started

```bash
# Install dependencies
npm install

# Start development server
npm start

# Run on iOS
npm run ios

# Run on Android
npm run android
```

## Design Philosophy

The app intentionally limits functionality to basic browsing and two swipe actions. Any interaction beyond viewing or hiding posts opens the native browser, keeping the app lightweight and well within Reddit's API rate limits (100 requests per minute).
