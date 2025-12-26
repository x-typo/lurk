import { RedditListing, RedditPost, TimeFilter, SortType } from '../types/reddit';

const BASE_URL = 'https://www.reddit.com';

export async function fetchPopularPosts(
  sort: SortType = 'top',
  time: TimeFilter = 'day',
  after?: string
): Promise<RedditListing<RedditPost>> {
  const params = new URLSearchParams({
    sort,
    t: time,
    limit: '25',
    raw_json: '1',
  });

  if (after) {
    params.append('after', after);
  }

  const response = await fetch(
    `${BASE_URL}/r/popular/${sort}.json?${params.toString()}`
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch posts: ${response.status}`);
  }

  return response.json();
}

export async function fetchSubredditPosts(
  subreddit: string,
  sort: SortType = 'hot',
  after?: string
): Promise<RedditListing<RedditPost>> {
  const params = new URLSearchParams({
    limit: '25',
    raw_json: '1',
  });

  if (after) {
    params.append('after', after);
  }

  const response = await fetch(
    `${BASE_URL}/r/${subreddit}/${sort}.json?${params.toString()}`
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch posts: ${response.status}`);
  }

  return response.json();
}

