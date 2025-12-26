import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  ActivityIndicator,
  RefreshControl,
  TouchableOpacity,
} from 'react-native';
import { useAuth } from '../context/AuthContext';
import { fetchHomePosts } from '../api/reddit';
import { PostCard } from '../components/PostCard';
import { RedditPost } from '../types/reddit';
import { colors } from '../constants/colors';

export function HomeScreen() {
  const { isAuthenticated, isLoading: authLoading, accessToken, signIn } = useAuth();
  const [posts, setPosts] = useState<RedditPost[]>([]);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [after, setAfter] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const loadPosts = useCallback(async () => {
    if (!accessToken) return;

    try {
      setLoading(true);
      const response = await fetchHomePosts(accessToken, 'hot');
      setPosts(response.data.children.map((child) => child.data));
      setAfter(response.data.after);
    } catch (err) {
      console.error('Failed to load home posts:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [accessToken]);

  const loadMore = useCallback(async () => {
    if (!after || loadingMore || !accessToken) return;

    try {
      setLoadingMore(true);
      const response = await fetchHomePosts(accessToken, 'hot', after);
      setPosts((prev) => [
        ...prev,
        ...response.data.children.map((child) => child.data),
      ]);
      setAfter(response.data.after);
    } catch (err) {
      console.error('Failed to load more:', err);
    } finally {
      setLoadingMore(false);
    }
  }, [after, loadingMore, accessToken]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadPosts();
  }, [loadPosts]);

  useEffect(() => {
    if (isAuthenticated && accessToken) {
      loadPosts();
    }
  }, [isAuthenticated, accessToken, loadPosts]);

  if (authLoading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (!isAuthenticated) {
    return (
      <View style={styles.centered}>
        <TouchableOpacity onPress={signIn}>
          <Text style={styles.signInText}>Sign in to see your home feed</Text>
        </TouchableOpacity>
        <Text style={styles.subtext}>
          Your subscribed subreddits will appear here
        </Text>
      </View>
    );
  }

  if (loading && posts.length === 0) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <FlatList
      data={posts}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => <PostCard post={item} />}
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
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
    padding: 20,
  },
  signInText: {
    color: colors.primary,
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
  subtext: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
  list: {
    flex: 1,
    backgroundColor: colors.background,
  },
  footer: {
    padding: 20,
  },
});
