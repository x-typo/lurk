import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  Modal,
  TouchableOpacity,
  ScrollView,
  Image,
  Dimensions,
  Linking,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { RedditPost } from '../types/reddit';
import { colors } from '../constants/colors';

const SCREEN_WIDTH = Dimensions.get('window').width;

interface PostDetailProps {
  post: RedditPost | null;
  visible: boolean;
  onClose: () => void;
}

function decodeHtmlEntities(str: string): string {
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function formatTimeAgo(utcSeconds: number): string {
  const now = Date.now() / 1000;
  const diff = now - utcSeconds;

  if (diff < 60) return 'now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}d`;
  return `${Math.floor(diff / 604800)}w`;
}

function formatScore(score: number): string {
  if (score >= 1000000) return `${(score / 1000000).toFixed(1)}M`;
  if (score >= 1000) return `${(score / 1000).toFixed(1)}k`;
  return score.toString();
}

function getImageUrl(post: RedditPost): { url: string; width: number; height: number } | null {
  if (post.preview?.images?.[0]?.source) {
    const source = post.preview.images[0].source;
    return {
      url: decodeHtmlEntities(source.url),
      width: source.width,
      height: source.height,
    };
  }
  return null;
}

export function PostDetail({ post, visible, onClose }: PostDetailProps) {
  const insets = useSafeAreaInsets();

  if (!post) return null;

  const imageData = getImageUrl(post);
  const imageHeight = imageData
    ? (SCREEN_WIDTH / imageData.width) * imageData.height
    : 0;

  const openInSafari = () => {
    const url = `https://www.reddit.com${post.permalink}`;
    Linking.openURL(url);
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeText}>Close</Text>
          </TouchableOpacity>
          <TouchableOpacity onPress={openInSafari} style={styles.safariButton}>
            <Text style={styles.safariText}>Open in Safari</Text>
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.meta}>
            <Text style={styles.subreddit}>{post.subreddit_name_prefixed}</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.time}>{formatTimeAgo(post.created_utc)}</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.author}>u/{post.author}</Text>
          </View>

          <Text style={styles.title}>{post.title}</Text>

          {imageData && (
            <Image
              source={{ uri: imageData.url }}
              style={[styles.image, { height: Math.min(imageHeight, 400) }]}
              resizeMode="contain"
            />
          )}

          {post.selftext && post.selftext.length > 0 && (
            <Text style={styles.selftext}>{post.selftext}</Text>
          )}

          <View style={styles.stats}>
            <Text style={styles.stat}>{formatScore(post.score)} points</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.stat}>{formatScore(post.num_comments)} comments</Text>
          </View>
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  closeButton: {
    padding: 4,
  },
  closeText: {
    color: colors.primary,
    fontSize: 17,
    fontWeight: '600',
  },
  safariButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  safariText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  content: {
    flex: 1,
    padding: 16,
  },
  meta: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    marginBottom: 12,
  },
  subreddit: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  dot: {
    color: colors.textMuted,
    marginHorizontal: 6,
    fontSize: 12,
  },
  time: {
    color: colors.textMuted,
    fontSize: 14,
  },
  author: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  title: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    lineHeight: 26,
    marginBottom: 16,
  },
  image: {
    width: '100%',
    backgroundColor: colors.surfaceElevated,
    borderRadius: 8,
    marginBottom: 16,
  },
  selftext: {
    color: colors.textSecondary,
    fontSize: 16,
    lineHeight: 24,
    marginBottom: 16,
  },
  stats: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  stat: {
    color: colors.textSecondary,
    fontSize: 14,
  },
});
