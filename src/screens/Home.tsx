import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  FlatList,
  ActivityIndicator,
  RefreshControl,
  StyleSheet,
  Text,
} from 'react-native';
import { fetchSubredditPosts } from '../api/reddit';
import { RedditPost } from '../types/reddit';
import { PostCard } from '../components/PostCard';
import { colors } from '../constants/colors';
import { usePostFilter } from '../context/PostFilterContext';
import { useSubreddits } from '../context/SubredditContext';

export function Home() {
  const [posts, setPosts] = useState<RedditPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { isHidden, hidePost } = usePostFilter();
  const { subreddits } = useSubreddits();

  // isHidden reads from a ref (always current), so it's not in the dep array.
  // loadPosts re-runs when subreddits change (user adds/removes a sub).
  const loadPosts = useCallback(async () => {
    if (subreddits.length === 0) {
      setPosts([]);
      setLoading(false);
      setRefreshing(false);
      return;
    }

    try {
      setError(null);
      const responses = await Promise.all(
        subreddits.map((sub) => fetchSubredditPosts(sub, 'hot')),
      );
      const allPosts = responses
        .flatMap((r) => r.data.children.map((c) => c.data))
        .filter((p) => !isHidden(p.id));
      allPosts.sort((a, b) => b.created_utc - a.created_utc);
      setPosts(allPosts);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load posts');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [subreddits]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadPosts();
  }, [loadPosts]);

  useEffect(() => {
    loadPosts();
  }, [loadPosts]);

  const handleHide = useCallback(
    (id: string) => {
      hidePost(id);
      setPosts((prev) => prev.filter((p) => p.id !== id));
    },
    [hidePost],
  );

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (subreddits.length === 0) {
    return (
      <View style={styles.centered}>
        <Text style={styles.emptyText}>No subreddits followed</Text>
        <Text style={styles.emptySubtext}>Add some in the Subreddits tab</Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>{error}</Text>
      </View>
    );
  }

  return (
    <FlatList
      data={posts}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => <PostCard post={item} onHide={handleHide} />}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={onRefresh}
          tintColor={colors.primary}
        />
      }
      style={styles.list}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
    padding: 20,
  },
  emptyText: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
  emptySubtext: {
    color: colors.textSecondary,
    fontSize: 15,
  },
  errorText: {
    color: colors.textSecondary,
    fontSize: 16,
  },
});
