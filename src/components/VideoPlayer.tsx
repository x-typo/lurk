import React, { useCallback, useEffect } from "react";
import {
  Modal,
  View,
  StyleSheet,
  Dimensions,
  StatusBar,
  ActivityIndicator,
  Text,
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
import { colors } from "../constants/colors";

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get("window");
const DISMISS_THRESHOLD = 100;

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

  useEffect(() => {
    if (visible) {
      player.play();
    } else {
      player.pause();
    }
  }, [visible, player]);

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

  const tapGesture = Gesture.Tap().onEnd(() => {
    runOnJS(handleClose)();
  });

  const composedGesture = Gesture.Race(panGesture, tapGesture);

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
        <GestureDetector gesture={composedGesture}>
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
              <VideoView
                player={player}
                style={{ width: displayWidth, height: displayHeight }}
                contentFit="contain"
                nativeControls
              />
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
});
