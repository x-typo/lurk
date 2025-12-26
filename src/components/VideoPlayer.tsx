import React, { useState, useRef, useCallback } from "react";
import {
  Modal,
  View,
  StyleSheet,
  Dimensions,
  StatusBar,
  ActivityIndicator,
  Text,
} from "react-native";
import { Video, ResizeMode, AVPlaybackStatus } from "expo-av";
import { GestureHandlerRootView, Gesture, GestureDetector } from "react-native-gesture-handler";
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
  const videoRef = useRef<Video>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const translateY = useSharedValue(0);

  const aspectRatio = videoWidth / videoHeight;

  let displayWidth = SCREEN_WIDTH;
  let displayHeight = SCREEN_WIDTH / aspectRatio;

  if (displayHeight > SCREEN_HEIGHT * 0.8) {
    displayHeight = SCREEN_HEIGHT * 0.8;
    displayWidth = displayHeight * aspectRatio;
  }

  const handlePlaybackStatusUpdate = (status: AVPlaybackStatus) => {
    if (status.isLoaded) {
      setIsLoading(false);
      setError(null);
    }
  };

  const handleError = (errorMessage: string) => {
    setIsLoading(false);
    setError(errorMessage);
  };

  const handleClose = useCallback(() => {
    setIsLoading(true);
    setError(null);
    translateY.value = 0;
    onClose();
  }, [onClose, translateY]);

  const panGesture = Gesture.Pan()
    .onUpdate((event) => {
      // Only allow swipe down (positive Y)
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
            {error ? (
              <View style={styles.errorContainer}>
                <Text style={styles.errorText}>Failed to load video</Text>
              </View>
            ) : (
              <Video
                ref={videoRef}
                source={{ uri: videoUrl }}
                style={{ width: displayWidth, height: displayHeight }}
                resizeMode={ResizeMode.CONTAIN}
                shouldPlay={visible}
                isLooping
                useNativeControls
                onPlaybackStatusUpdate={handlePlaybackStatusUpdate}
                onError={() => handleError("Video playback error")}
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
