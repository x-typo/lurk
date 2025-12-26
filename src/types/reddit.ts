export interface RedditPost {
  id: string;
  title: string;
  author: string;
  subreddit: string;
  subreddit_name_prefixed: string;
  score: number;
  num_comments: number;
  created_utc: number;
  permalink: string;
  url: string;
  thumbnail: string;
  thumbnail_width?: number;
  thumbnail_height?: number;
  selftext: string;
  is_self: boolean;
  is_video: boolean;
  stickied: boolean;
  over_18: boolean;
  post_hint?: string;
  media?: {
    reddit_video?: {
      fallback_url: string;
      height: number;
      width: number;
      duration: number;
    };
  };
  preview?: {
    images: Array<{
      source: {
        url: string;
        width: number;
        height: number;
      };
      resolutions: Array<{
        url: string;
        width: number;
        height: number;
      }>;
    }>;
  };
  gallery_data?: {
    items: Array<{
      media_id: string;
      id: number;
    }>;
  };
  media_metadata?: Record<string, {
    s: {
      u: string;
      x: number;
      y: number;
    };
  }>;
}

export interface RedditListing<T> {
  kind: string;
  data: {
    after: string | null;
    before: string | null;
    children: Array<{
      kind: string;
      data: T;
    }>;
  };
}

export type TimeFilter = 'hour' | 'day' | 'week' | 'month' | 'year' | 'all';
export type SortType = 'hot' | 'new' | 'top' | 'rising';
