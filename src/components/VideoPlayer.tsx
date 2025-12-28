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
  const progressBarWidth = useRef(0);
  const progressBarX = useRef(0);
  const [isScrubbing, setIsScrubbing] = useState(false);
  const [scrubbingTime, setScrubbingTime] = useState(0);

  useEffect(() => {
    setIsPlaying(playerIsPlaying);
  }, [playerIsPlaying]);

  useEffect(() => {
    if (!visible || !player) return;

    const interval = setInterval(() => {
      setCurrentTime(player.currentTime);
      setDuration(player.duration);
    }, 250);

    return () => clearInterval(interval);
  }, [visible, player]);

  const startHideTimer = useCallback(() => {
    if (hideControlsTimer.current) {
      clearTimeout(hideControlsTimer.current);
    }
    hideControlsTimer.current = setTimeout(() => {
      if (player.playing) {
        setShowControls(false);
      }
    }, 1000);
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

  const seekToPosition = useCallback(
    (locationX: number) => {
      if (duration > 0 && progressBarWidth.current > 0) {
        const ratio = Math.max(0, Math.min(1, locationX / progressBarWidth.current));
        const seekTime = ratio * duration;
        return seekTime;
      }
      return 0;
    },
    [duration]
  );

  const startScrubbing = useCallback((time: number) => {
    setIsScrubbing(true);
    setScrubbingTime(time);
    clearHideTimer();
  }, [clearHideTimer]);

  const updateScrubbing = useCallback((time: number) => {
    setScrubbingTime(time);
  }, []);

  const endScrubbing = useCallback((time: number) => {
    player.currentTime = time;
    setIsScrubbing(false);
    if (player.playing) {
      startHideTimer();
    }
  }, [player, startHideTimer]);

  const progressGesture = Gesture.Pan()
    .onStart((event) => {
      const seekTime = seekToPosition(event.x);
      runOnJS(startScrubbing)(seekTime);
    })
    .onUpdate((event) => {
      const seekTime = seekToPosition(event.x);
      runOnJS(updateScrubbing)(seekTime);
    })
    .onEnd((event) => {
      const seekTime = seekToPosition(event.x);
      runOnJS(endScrubbing)(seekTime);
    });

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
                      <Text style={styles.timeText}>
                        {formatTime(isScrubbing ? scrubbingTime : currentTime)}
                      </Text>
                      <GestureDetector gesture={progressGesture}>
                        <View
                          style={styles.progressBarContainer}
                          onLayout={(e) => {
                            progressBarWidth.current = e.nativeEvent.layout.width;
                            progressBarX.current = e.nativeEvent.layout.x;
                          }}
                        >
                          <View style={styles.progressBarBackground}>
                            <View
                              style={[
                                styles.progressBarFill,
                                {
                                  width: duration > 0
                                    ? `${((isScrubbing ? scrubbingTime : currentTime) / duration) * 100}%`
                                    : "0%",
                                },
                              ]}
                            />
                          </View>
                        </View>
                      </GestureDetector>
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
    gap: 10,
  },
  timeText: {
    color: colors.text,
    fontSize: 12,
    minWidth: 40,
    textAlign: "center",
  },
  progressBarContainer: {
    flex: 1,
    height: 30,
    justifyContent: "center",
  },
  progressBarBackground: {
    height: 4,
    backgroundColor: "rgba(255, 255, 255, 0.3)",
    borderRadius: 2,
    overflow: "hidden",
  },
  progressBarFill: {
    height: "100%",
    backgroundColor: colors.primary,
    borderRadius: 2,
  },
});
