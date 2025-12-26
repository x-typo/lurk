import React, { useMemo, useCallback, useState } from "react";
import {
  View,
  Text,
  Image,
  StyleSheet,
  Dimensions,
  Linking,
  TouchableOpacity,
} from "react-native";
import { ImageViewer } from "./ImageViewer";
import { VideoPlayer } from "./VideoPlayer";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
} from "react-native-reanimated";
import { RedditPost } from "../types/reddit";
import { colors } from "../constants/colors";

const SCREEN_WIDTH = Dimensions.get("window").width;
const SWIPE_THRESHOLD = 100;

interface PostCardProps {
  post: RedditPost;
  onHide?: (postId: string) => void;
}

function formatTimeAgo(utcSeconds: number): string {
  const now = Date.now() / 1000;
  const diff = now - utcSeconds;

  if (diff < 60) return "now";
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

function decodeHtmlEntities(str: string): string {
  return str.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
}

function getImageUrl(
  post: RedditPost
): { url: string; width: number; height: number } | null {
  // Check for preview images first
  if (post.preview?.images?.[0]?.source) {
    const source = post.preview.images[0].source;
    return {
      url: decodeHtmlEntities(source.url),
      width: source.width,
      height: source.height,
    };
  }

  // Check for gallery posts
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

export function PostCard({ post, onHide }: PostCardProps) {
  const imageData = useMemo(() => getImageUrl(post), [post]);
  const [imageViewerVisible, setImageViewerVisible] = useState(false);
  const [videoPlayerVisible, setVideoPlayerVisible] = useState(false);
  const translateX = useSharedValue(0);

  const videoData = useMemo(() => {
    if (post.is_video && post.media?.reddit_video) {
      const { fallback_url, width, height } = post.media.reddit_video;
      return { url: fallback_url, width, height };
    }
    return null;
  }, [post]);

  const imageHeight = useMemo(() => {
    if (!imageData) return 0;
    const aspectRatio = imageData.width / imageData.height;
    return SCREEN_WIDTH / aspectRatio;
  }, [imageData]);

  const openInBrowser = useCallback(() => {
    const url = `https://www.reddit.com${post.permalink}`;
    Linking.openURL(url);
  }, [post.permalink]);

  const hidePost = useCallback(() => {
    onHide?.(post.id);
  }, [post.id, onHide]);

  const panGesture = Gesture.Pan()
    .activeOffsetX([-20, 20])
    .onUpdate((event) => {
      translateX.value = event.translationX;
    })
    .onEnd((event) => {
      if (event.translationX > SWIPE_THRESHOLD) {
        runOnJS(openInBrowser)();
      } else if (event.translationX < -SWIPE_THRESHOLD) {
        runOnJS(hidePost)();
      }
      translateX.value = withSpring(0);
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  return (
    <View style={styles.swipeContainer}>
      <View style={styles.swipeBackgroundLeft} />
      <View style={styles.swipeBackgroundRight} />
      <GestureDetector gesture={panGesture}>
        <Animated.View style={[styles.container, animatedStyle]}>
          <View style={styles.header}>
            <Text style={styles.subreddit}>{post.subreddit_name_prefixed}</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.time}>{formatTimeAgo(post.created_utc)}</Text>
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
                style={[styles.image, { height: imageHeight }]}
                resizeMode="contain"
              />
              {post.is_video && (
                <View style={styles.videoIndicator}>
                  <Text style={styles.videoText}>▶</Text>
                </View>
              )}
            </TouchableOpacity>
          )}

          <View style={styles.footer}>
            <Text style={styles.score}>{formatScore(post.score)}</Text>
            <Text style={styles.dot}>•</Text>
            <Text style={styles.comments}>
              {formatScore(post.num_comments)} comments
            </Text>
          </View>
        </Animated.View>
      </GestureDetector>

      {imageData && (
        <ImageViewer
          visible={imageViewerVisible}
          imageUrl={imageData.url}
          imageWidth={imageData.width}
          imageHeight={imageData.height}
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
    </View>
  );
}

const styles = StyleSheet.create({
  swipeContainer: {
    position: "relative",
    overflow: "hidden",
  },
  swipeBackgroundLeft: {
    position: "absolute",
    top: 0,
    left: 0,
    bottom: 0,
    width: SWIPE_THRESHOLD + 20,
    backgroundColor: "#007AFF",
  },
  swipeBackgroundRight: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    width: SWIPE_THRESHOLD + 20,
    backgroundColor: "#FF3B30",
  },
  container: {
    backgroundColor: colors.surface,
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 8,
  },
  subreddit: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: "600",
  },
  dot: {
    color: colors.textMuted,
    marginHorizontal: 6,
    fontSize: 12,
  },
  time: {
    color: colors.textMuted,
    fontSize: 13,
  },
  title: {
    color: colors.text,
    fontSize: 16,
    lineHeight: 22,
    marginBottom: 12,
  },
  imageContainer: {
    marginHorizontal: -16,
    marginBottom: 12,
    position: "relative",
  },
  image: {
    width: "100%",
    backgroundColor: colors.surfaceElevated,
  },
  videoIndicator: {
    position: "absolute",
    top: "50%",
    left: "50%",
    transform: [{ translateX: -20 }, { translateY: -20 }],
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: "rgba(0, 0, 0, 0.7)",
    justifyContent: "center",
    alignItems: "center",
  },
  videoText: {
    color: colors.text,
    fontSize: 16,
  },
  footer: {
    flexDirection: "row",
    alignItems: "center",
  },
  score: {
    color: colors.textSecondary,
    fontSize: 13,
  },
  comments: {
    color: colors.textSecondary,
    fontSize: 13,
  },
});
