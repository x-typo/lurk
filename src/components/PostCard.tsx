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
import { PostDetail } from "./PostDetail";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
} from "react-native-reanimated";
import { RedditPost } from "../types/reddit";
import { colors } from "../constants/colors";
import { decodeHtmlEntities, formatTimeAgo, formatScore } from "../utils/format";

const SCREEN_WIDTH = Dimensions.get("window").width;
const SWIPE_THRESHOLD = 100;

interface PostCardProps {
  post: RedditPost;
}

interface ImageData {
  url: string;
  width: number;
  height: number;
}

function getImageUrl(post: RedditPost): ImageData | null {
  // Check for preview images first
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

export function PostCard({ post }: PostCardProps) {
  const imageData = useMemo(() => getImageUrl(post), [post]);
  const galleryImages = useMemo(() => getGalleryImages(post), [post]);
  const isGallery = galleryImages.length > 1;
  const [imageViewerVisible, setImageViewerVisible] = useState(false);
  const [videoPlayerVisible, setVideoPlayerVisible] = useState(false);
  const [detailVisible, setDetailVisible] = useState(false);
  const translateX = useSharedValue(0);

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

  const openDetail = useCallback(() => {
    setDetailVisible(true);
  }, []);

  const panGesture = Gesture.Pan()
    .activeOffsetX([-20, 20])
    .onUpdate((event) => {
      translateX.value = Math.max(0, event.translationX);
    })
    .onEnd((event) => {
      if (event.translationX > SWIPE_THRESHOLD) {
        runOnJS(openInBrowser)();
      }
      translateX.value = withSpring(0);
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  return (
    <View style={styles.swipeContainer}>
      <View style={styles.swipeBackgroundLeft} />
      <GestureDetector gesture={panGesture}>
        <Animated.View style={[styles.container, animatedStyle]}>
          <TouchableOpacity onPress={openDetail} activeOpacity={0.7}>
            <View style={styles.header}>
              <Text style={styles.subreddit}>{post.subreddit_name_prefixed}</Text>
              <Text style={styles.dot}>•</Text>
              <Text style={styles.time}>{formatTimeAgo(post.created_utc)}</Text>
            </View>

            <Text style={styles.title}>{post.title}</Text>
          </TouchableOpacity>

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

          <TouchableOpacity onPress={openDetail} activeOpacity={0.7}>
            <View style={styles.footer}>
              <Text style={styles.score}>{formatScore(post.score)}</Text>
              <Text style={styles.upvoteIcon}>△</Text>
              <Text style={styles.dot}>•</Text>
              <Text style={styles.comments}>
                {formatScore(post.num_comments)} comments
              </Text>
            </View>
          </TouchableOpacity>
        </Animated.View>
      </GestureDetector>

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

      <PostDetail
        post={post}
        visible={detailVisible}
        onClose={() => setDetailVisible(false)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  swipeContainer: {
    position: "relative",
    overflow: "hidden",
    marginHorizontal: 12,
    marginTop: 12,
    borderRadius: 12,
  },
  swipeBackgroundLeft: {
    position: "absolute",
    top: 0,
    left: 0,
    bottom: 0,
    width: SWIPE_THRESHOLD + 20,
    backgroundColor: "#007AFF",
    borderTopLeftRadius: 12,
    borderBottomLeftRadius: 12,
  },
  container: {
    backgroundColor: colors.surface,
    padding: 16,
    borderRadius: 12,
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
    marginBottom: 12,
    position: "relative",
    borderRadius: 8,
    overflow: "hidden",
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
  galleryIndicator: {
    position: "absolute",
    bottom: 12,
    left: 0,
    right: 0,
    flexDirection: "row",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
  },
  galleryDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: "rgba(255, 255, 255, 0.5)",
  },
  galleryDotActive: {
    backgroundColor: colors.text,
  },
  galleryMoreText: {
    color: colors.text,
    fontSize: 12,
    marginLeft: 4,
  },
  footer: {
    flexDirection: "row",
    alignItems: "center",
  },
  score: {
    color: colors.textSecondary,
    fontSize: 13,
  },
  upvoteIcon: {
    color: colors.textSecondary,
    fontSize: 12,
    marginLeft: 4,
  },
  comments: {
    color: colors.textSecondary,
    fontSize: 13,
  },
});
