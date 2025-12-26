import React, { useCallback } from "react";
import {
  Modal,
  View,
  Image,
  StyleSheet,
  Dimensions,
  StatusBar,
} from "react-native";
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

interface ImageViewerProps {
  visible: boolean;
  imageUrl: string;
  imageWidth: number;
  imageHeight: number;
  onClose: () => void;
}

export function ImageViewer({
  visible,
  imageUrl,
  imageWidth,
  imageHeight,
  onClose,
}: ImageViewerProps) {
  const translateY = useSharedValue(0);

  const aspectRatio = imageWidth / imageHeight;

  let displayWidth = SCREEN_WIDTH;
  let displayHeight = SCREEN_WIDTH / aspectRatio;

  if (displayHeight > SCREEN_HEIGHT * 0.8) {
    displayHeight = SCREEN_HEIGHT * 0.8;
    displayWidth = displayHeight * aspectRatio;
  }

  const handleClose = useCallback(() => {
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
            <Image
              source={{ uri: imageUrl }}
              style={{ width: displayWidth, height: displayHeight }}
              resizeMode="contain"
            />
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
});
