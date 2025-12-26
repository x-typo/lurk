import React, { useState, useMemo } from 'react';
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
import { ImageViewer } from './ImageViewer';
import { VideoPlayer } from './VideoPlayer';

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

interface ImageData {
  url: string;
  width: number;
  height: number;
}

function getImageUrl(post: RedditPost): ImageData | null {
  if (post.preview?.images?.[0]?.source) {
    const source = post.preview.images[0].source;
    return {
      url: decodeHtmlEntities(source.url),
      width: source.width,
      height: source.height,
    };
  }

  // Check for gallery posts - return first image for thumbnail
  if (post.gallery_data?.items?.[0] && post.media_metadata) {
    const firstItem = post.gallery_data.items[0];
    const mediaInfo = post.media_metadata[firstItem.media_id];
    if (mediaInfo?.s) {
      return {
        url: decodeHtmlEntities(mediaInfo.s.u),
        width: mediaInfo.s.x,
        height: mediaInfo.s.y,
      };
    }
  }

  return null;
}

function getGalleryImages(post: RedditPost): ImageData[] {
  if (!post.gallery_data?.items || !post.media_metadata) {
    return [];
  }

  return post.gallery_data.items
    .map((item) => {
      const mediaInfo = post.media_metadata?.[item.media_id];
      if (mediaInfo?.s) {
        return {
          url: decodeHtmlEntities(mediaInfo.s.u),
          width: mediaInfo.s.x,
          height: mediaInfo.s.y,
        };
      }
      return null;
    })
    .filter((img): img is ImageData => img !== null);
}

export function PostDetail({ post, visible, onClose }: PostDetailProps) {
  const insets = useSafeAreaInsets();
  const [imageViewerVisible, setImageViewerVisible] = useState(false);
  const [videoPlayerVisible, setVideoPlayerVisible] = useState(false);

  const imageData = useMemo(() => (post ? getImageUrl(post) : null), [post]);
  const galleryImages = useMemo(() => (post ? getGalleryImages(post) : []), [post]);
  const isGallery = galleryImages.length > 1;

  const viewerImages = useMemo(() => {
    if (isGallery) {
      return galleryImages;
    }
    if (imageData) {
      return [imageData];
    }
    return [];
  }, [isGallery, galleryImages, imageData]);

  const videoData = useMemo(() => {
    if (post?.is_video && post.media?.reddit_video) {
      const { fallback_url, width, height } = post.media.reddit_video;
      return { url: fallback_url, width, height };
    }
    return null;
  }, [post]);

  const imageHeight = imageData
    ? (SCREEN_WIDTH / imageData.width) * imageData.height
    : 0;

  if (!post) return null;

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
      onDismiss={onClose}
    >
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeText}>Close</Text>
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
            <TouchableOpacity
              activeOpacity={0.9}
              onPress={() => {
                if (videoData) {
                  setVideoPlayerVisible(true);
                } else {
                  setImageViewerVisible(true);
                }
              }}
              style={styles.imageContainer}
            >
              <Image
                source={{ uri: imageData.url }}
                style={[styles.image, { height: Math.min(imageHeight, 400) }]}
                resizeMode="contain"
              />
              {post.is_video && (
                <View style={styles.videoIndicator}>
                  <Text style={styles.videoText}>▶</Text>
                </View>
              )}
              {isGallery && (
                <View style={styles.galleryIndicator}>
                  {galleryImages.slice(0, 5).map((_, index) => (
                    <View
                      key={index}
                      style={[
                        styles.galleryDot,
                        index === 0 && styles.galleryDotActive,
                      ]}
                    />
                  ))}
                  {galleryImages.length > 5 && (
                    <Text style={styles.galleryMoreText}>+{galleryImages.length - 5}</Text>
                  )}
                </View>
              )}
            </TouchableOpacity>
          )}

          {post.selftext && post.selftext.length > 0 && (
            <Text style={styles.selftext}>{post.selftext}</Text>
          )}

          <View style={styles.stats}>
            <Text style={styles.stat}>{formatScore(post.score)} points</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.stat}>{formatScore(post.num_comments)} comments</Text>
          </View>

          <TouchableOpacity onPress={openInSafari} style={styles.safariButton}>
            <Text style={styles.safariText}>Open in Safari</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>

      {viewerImages.length > 0 && (
        <ImageViewer
          visible={imageViewerVisible}
          images={viewerImages}
          onClose={() => setImageViewerVisible(false)}
        />
      )}

      {videoData && (
        <VideoPlayer
          visible={videoPlayerVisible}
          videoUrl={videoData.url}
          videoWidth={videoData.width}
          videoHeight={videoData.height}
          onClose={() => setVideoPlayerVisible(false)}
        />
      )}
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
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    alignSelf: 'center',
    marginTop: 24,
    marginBottom: 16,
  },
  safariText: {
    color: colors.text,
    fontSize: 16,
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
  imageContainer: {
    position: 'relative',
    marginBottom: 16,
  },
  image: {
    width: '100%',
    backgroundColor: colors.surfaceElevated,
    borderRadius: 8,
  },
  videoIndicator: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    transform: [{ translateX: -25 }, { translateY: -25 }],
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  videoText: {
    color: colors.text,
    fontSize: 20,
  },
  galleryIndicator: {
    position: 'absolute',
    bottom: 12,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
  },
  galleryDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: 'rgba(255, 255, 255, 0.5)',
  },
  galleryDotActive: {
    backgroundColor: colors.text,
  },
  galleryMoreText: {
    color: colors.text,
    fontSize: 12,
    marginLeft: 4,
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
