import React, { useCallback, useEffect, useState, useRef } from "react";
import {
  Modal,
  View,
  StyleSheet,
  Dimensions,
  StatusBar,
  ActivityIndicator,
  Text,
  TouchableOpacity,
  Pressable,
} from "react-native";
import { useVideoPlayer, VideoView } from "expo-video";
import { useEvent } from "expo";
import Slider from "@react-native-community/slider";
import {
  GestureHandlerRootView,
  Gesture,
  GestureDetector,
} from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
  interpolate,
} from "react-native-reanimated";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "../constants/colors";

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get("window");
const DISMISS_THRESHOLD = 100;
const SKIP_SECONDS = 10;

interface VideoPlayerProps {
  visible: boolean;
  videoUrl: string;
  videoWidth: number;
  videoHeight: number;
  onClose: () => void;
}

export function VideoPlayer({
  visible,
  videoUrl,
  videoWidth,
  videoHeight,
  onClose,
}: VideoPlayerProps) {
  const translateY = useSharedValue(0);
  const [isPlaying, setIsPlaying] = useState(true);
  const [showControls, setShowControls] = useState(true);
  const hideControlsTimer = useRef<NodeJS.Timeout | null>(null);

  const aspectRatio = videoWidth / videoHeight;

  let displayWidth = SCREEN_WIDTH;
  let displayHeight = SCREEN_WIDTH / aspectRatio;

  if (displayHeight > SCREEN_HEIGHT * 0.8) {
    displayHeight = SCREEN_HEIGHT * 0.8;
    displayWidth = displayHeight * aspectRatio;
  }

  const player = useVideoPlayer(videoUrl, (p) => {
    p.loop = true;
  });

  const { status } = useEvent(player, "statusChange", {
    status: player.status,
  });

  const { isPlaying: playerIsPlaying } = useEvent(player, "playingChange", {
    isPlaying: player.playing,
  });

  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isScrubbing, setIsScrubbing] = useState(false);
  const [scrubbingTime, setScrubbingTime] = useState(0);

  useEffect(() => {
    setIsPlaying(playerIsPlaying);
  }, [playerIsPlaying]);

  useEffect(() => {
    if (!visible || !player) return;

    const interval = setInterval(() => {
      if (!isScrubbing) {
        setCurrentTime(player.currentTime);
      }
      setDuration(player.duration);
    }, 250);

    return () => clearInterval(interval);
  }, [visible, player, isScrubbing]);

  const startHideTimer = useCallback(() => {
    if (hideControlsTimer.current) {
      clearTimeout(hideControlsTimer.current);
    }
    hideControlsTimer.current = setTimeout(() => {
      if (player.playing) {
        setShowControls(false);
      }
    }, 2000);
  }, [player]);

  const clearHideTimer = useCallback(() => {
    if (hideControlsTimer.current) {
      clearTimeout(hideControlsTimer.current);
      hideControlsTimer.current = null;
    }
  }, []);

  useEffect(() => {
    if (visible) {
      player.play();
      setIsPlaying(true);
      setShowControls(true);
      startHideTimer();
    } else {
      player.pause();
      setIsPlaying(false);
      clearHideTimer();
    }
  }, [visible, player, startHideTimer, clearHideTimer]);

  const togglePlayPause = useCallback(() => {
    if (player.playing) {
      player.pause();
      clearHideTimer();
    } else {
      player.play();
      startHideTimer();
    }
  }, [player, startHideTimer, clearHideTimer]);

  const skipForward = useCallback(() => {
    player.seekBy(SKIP_SECONDS);
    if (player.playing) {
      startHideTimer();
    }
  }, [player, startHideTimer]);

  const skipBackward = useCallback(() => {
    player.seekBy(-SKIP_SECONDS);
    if (player.playing) {
      startHideTimer();
    }
  }, [player, startHideTimer]);

  const handleSlidingStart = useCallback(() => {
    setIsScrubbing(true);
    setScrubbingTime(currentTime);
    clearHideTimer();
  }, [currentTime, clearHideTimer]);

  const handleValueChange = useCallback((value: number) => {
    setScrubbingTime(value);
  }, []);

  const handleSlidingComplete = useCallback(
    (value: number) => {
      player.currentTime = value;
      setCurrentTime(value);
      setIsScrubbing(false);
      if (player.playing) {
        startHideTimer();
      }
    },
    [player, startHideTimer]
  );

  const formatTime = useCallback((seconds: number) => {
    if (!isFinite(seconds) || seconds < 0) return "0:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  }, []);

  const toggleControls = useCallback(() => {
    setShowControls((prev) => {
      const newValue = !prev;
      if (newValue && player.playing) {
        startHideTimer();
      } else {
        clearHideTimer();
      }
      return newValue;
    });
  }, [player, startHideTimer, clearHideTimer]);

  const handleClose = useCallback(() => {
    player.pause();
    translateY.value = 0;
    onClose();
  }, [onClose, translateY, player]);

  const panGesture = Gesture.Pan()
    .onUpdate((event) => {
      if (event.translationY > 0) {
        translateY.value = event.translationY;
      }
    })
    .onEnd((event) => {
      if (event.translationY > DISMISS_THRESHOLD) {
        runOnJS(handleClose)();
      } else {
        translateY.value = withSpring(0);
      }
    });

  const animatedContainerStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  const animatedOverlayStyle = useAnimatedStyle(() => {
    const opacity = interpolate(
      translateY.value,
      [0, SCREEN_HEIGHT * 0.4],
      [1, 0]
    );
    return { opacity };
  });

  if (!visible) return null;

  const isLoading = status === "loading";
  const hasError = status === "error";
  const displayTime = isScrubbing ? scrubbingTime : currentTime;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={handleClose}
    >
      <GestureHandlerRootView style={styles.gestureRoot}>
        <StatusBar hidden />
        <Animated.View style={[styles.overlay, animatedOverlayStyle]} />
        <GestureDetector gesture={panGesture}>
          <Animated.View style={[styles.gestureArea, animatedContainerStyle]}>
            {isLoading && (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={colors.primary} />
              </View>
            )}
            {hasError ? (
              <View style={styles.errorContainer}>
                <Text style={styles.errorText}>Failed to load video</Text>
              </View>
            ) : (
              <Pressable onPress={toggleControls} style={styles.videoContainer}>
                <VideoView
                  player={player}
                  style={{ width: displayWidth, height: displayHeight }}
                  contentFit="contain"
                  nativeControls={false}
                />
                {showControls && (
                  <View style={styles.controlsOverlay}>
                    <View style={styles.controlsRow}>
                      <TouchableOpacity
                        onPress={skipBackward}
                        style={styles.controlButton}
                        activeOpacity={0.7}
                      >
                        <Ionicons
                          name="play-back"
                          size={32}
                          color={colors.text}
                        />
                        <Text style={styles.skipText}>10</Text>
                      </TouchableOpacity>

                      <TouchableOpacity
                        onPress={togglePlayPause}
                        style={styles.playPauseButton}
                        activeOpacity={0.7}
                      >
                        <Ionicons
                          name={isPlaying ? "pause" : "play"}
                          size={48}
                          color={colors.text}
                        />
                      </TouchableOpacity>

                      <TouchableOpacity
                        onPress={skipForward}
                        style={styles.controlButton}
                        activeOpacity={0.7}
                      >
                        <Ionicons
                          name="play-forward"
                          size={32}
                          color={colors.text}
                        />
                        <Text style={styles.skipText}>10</Text>
                      </TouchableOpacity>
                    </View>

                    {/* Progress bar */}
                    <View style={styles.progressContainer}>
                      <Text style={styles.timeText}>{formatTime(displayTime)}</Text>
                      <View style={styles.sliderContainer}>
                        {/* Time preview bubble while scrubbing */}
                        {isScrubbing && (
                          <View
                            style={[
                              styles.timePreviewBubble,
                              {
                                left: duration > 0
                                  ? `${(scrubbingTime / duration) * 100}%`
                                  : "0%",
                              },
                            ]}
                          >
                            <Text style={styles.timePreviewText}>
                              {formatTime(scrubbingTime)}
                            </Text>
                          </View>
                        )}
                        <Slider
                          style={styles.slider}
                          minimumValue={0}
                          maximumValue={duration > 0 ? duration : 1}
                          value={displayTime}
                          onSlidingStart={handleSlidingStart}
                          onValueChange={handleValueChange}
                          onSlidingComplete={handleSlidingComplete}
                          minimumTrackTintColor={colors.primary}
                          maximumTrackTintColor="rgba(255, 255, 255, 0.3)"
                          thumbTintColor={colors.primary}
                        />
                      </View>
                      <Text style={styles.timeText}>{formatTime(duration)}</Text>
                    </View>
                  </View>
                )}
              </Pressable>
            )}

            {/* Close button */}
            {showControls && (
              <TouchableOpacity
                onPress={handleClose}
                style={styles.closeButton}
                activeOpacity={0.7}
              >
                <Ionicons name="close" size={28} color={colors.text} />
              </TouchableOpacity>
            )}
          </Animated.View>
        </GestureDetector>
      </GestureHandlerRootView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  gestureRoot: {
    flex: 1,
  },
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.95)",
  },
  gestureArea: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  videoContainer: {
    justifyContent: "center",
    alignItems: "center",
  },
  loadingContainer: {
    position: "absolute",
    justifyContent: "center",
    alignItems: "center",
  },
  errorContainer: {
    padding: 20,
  },
  errorText: {
    color: colors.textSecondary,
    fontSize: 16,
  },
  controlsOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "center",
    backgroundColor: "rgba(0, 0, 0, 0.3)",
  },
  controlsRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 40,
  },
  controlButton: {
    alignItems: "center",
    justifyContent: "center",
    padding: 12,
  },
  playPauseButton: {
    width: 80,
    height: 80,
    alignItems: "center",
    justifyContent: "center",
  },
  skipText: {
    color: colors.text,
    fontSize: 12,
    marginTop: 2,
  },
  closeButton: {
    position: "absolute",
    top: 50,
    right: 20,
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
  },
  progressContainer: {
    position: "absolute",
    bottom: 20,
    left: 20,
    right: 20,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  timeText: {
    color: colors.text,
    fontSize: 12,
    minWidth: 40,
    textAlign: "center",
  },
  sliderContainer: {
    flex: 1,
    height: 40,
    justifyContent: "center",
  },
  slider: {
    width: "100%",
    height: 40,
  },
  timePreviewBubble: {
    position: "absolute",
    top: -35,
    transform: [{ translateX: -30 }],
    backgroundColor: "rgba(0, 0, 0, 0.9)",
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    minWidth: 60,
    alignItems: "center",
    zIndex: 10,
  },
  timePreviewText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: "600",
  },
});
