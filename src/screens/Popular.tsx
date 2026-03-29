import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  FlatList,
  ActivityIndicator,
  RefreshControl,
  StyleSheet,
  Text,
} from 'react-native';
import { fetchPopularPosts } from '../api/reddit';
import { RedditPost } from '../types/reddit';
import { PostCard } from '../components/PostCard';
import { colors } from '../constants/colors';
import { usePostFilter } from '../context/PostFilterContext';

export function Popular() {
  const [posts, setPosts] = useState<RedditPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [after, setAfter] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { isHidden, hidePost } = usePostFilter();

  const handleHide = useCallback((id: string) => {
    hidePost(id);
    setPosts((prev) => prev.filter((p) => p.id !== id));
  }, [hidePost]);

  // isHidden reads from a ref (always current), not in dep array by design.
  const loadPosts = useCallback(async () => {
    try {
      setError(null);
      const response = await fetchPopularPosts('top', 'day');
      const allPosts = response.data.children.map((child) => child.data);
      setPosts(allPosts.filter((p) => !isHidden(p.id)));
      setAfter(response.data.after);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load posts');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  const loadMore = useCallback(async () => {
    if (loadingMore || !after) return;

    setLoadingMore(true);
    try {
      const response = await fetchPopularPosts('top', 'day', after);
      const newPosts = response.data.children
        .map((child) => child.data)
        .filter((p) => !isHidden(p.id));
      setPosts((prev) => [...prev, ...newPosts]);
      setAfter(response.data.after);
    } catch (err) {
      console.error('Failed to load more:', err);
    } finally {
      setLoadingMore(false);
    }
  }, [after, loadingMore]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadPosts();
  }, [loadPosts]);

  useEffect(() => {
    loadPosts();
  }, [loadPosts]);

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={colors.primary} />
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
      onEndReached={loadMore}
      onEndReachedThreshold={0.5}
      ListFooterComponent={
        loadingMore ? (
          <View style={styles.footer}>
            <ActivityIndicator color={colors.primary} />
          </View>
        ) : null
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
  },
  footer: {
    padding: 20,
  },
  errorText: {
    color: colors.textSecondary,
    fontSize: 16,
  },
});
