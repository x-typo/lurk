import React, { useCallback } from "react";
import {
  Modal,
  View,
  Image,
  StyleSheet,
  Dimensions,
  StatusBar,
} from "react-native";
import {
  GestureHandlerRootView,
  Gesture,
  GestureDetector,
} from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  runOnJS,
  interpolate,
  SharedValue,
} from "react-native-reanimated";
import { colors } from "../constants/colors";

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get("window");
const DISMISS_THRESHOLD = 100;
const SWIPE_THRESHOLD = 50;

interface ImageData {
  url: string;
  width: number;
  height: number;
}

interface ImageViewerProps {
  visible: boolean;
  images: ImageData[];
  initialIndex?: number;
  onClose: () => void;
}

interface IndicatorProps {
  index: number;
  offsetX: SharedValue<number>;
  dragX: SharedValue<number>;
}

function Indicator({ index, offsetX, dragX }: IndicatorProps) {
  const animatedStyle = useAnimatedStyle(() => {
    const currentPos = -(offsetX.value + dragX.value) / SCREEN_WIDTH;
    const distance = Math.abs(currentPos - index);
    const isActive = distance < 0.5;
    return {
      backgroundColor: isActive ? colors.text : colors.textMuted,
    };
  });

  return <Animated.View style={[styles.indicator, animatedStyle]} />;
}

export function ImageViewer({
  visible,
  images,
  initialIndex = 0,
  onClose,
}: ImageViewerProps) {
  const translateY = useSharedValue(0);
  const offsetX = useSharedValue(-initialIndex * SCREEN_WIDTH);
  const dragX = useSharedValue(0);
  const currentIndexValue = useSharedValue(initialIndex);

  const handleClose = useCallback(() => {
    translateY.value = 0;
    dragX.value = 0;
    offsetX.value = -initialIndex * SCREEN_WIDTH;
    currentIndexValue.value = initialIndex;
    onClose();
  }, [onClose, translateY, dragX, offsetX, initialIndex, currentIndexValue]);

  const panGesture = Gesture.Pan()
    .onUpdate((event) => {
      // Determine if horizontal or vertical swipe
      if (
        images.length > 1 &&
        Math.abs(event.translationX) > Math.abs(event.translationY)
      ) {
        // Horizontal swipe - follow finger
        dragX.value = event.translationX;
      } else if (event.translationY > 0) {
        // Vertical swipe down to dismiss
        translateY.value = event.translationY;
      }
    })
    .onEnd((event) => {
      const currentIdx = currentIndexValue.value;

      // Handle horizontal swipe for image navigation
      if (
        images.length > 1 &&
        Math.abs(event.translationX) > Math.abs(event.translationY)
      ) {
        let newIndex = currentIdx;

        if (event.translationX < -SWIPE_THRESHOLD && currentIdx < images.length - 1) {
          newIndex = currentIdx + 1;
        } else if (event.translationX > SWIPE_THRESHOLD && currentIdx > 0) {
          newIndex = currentIdx - 1;
        }

        currentIndexValue.value = newIndex;
        // Animate to the new position
        offsetX.value = withTiming(-newIndex * SCREEN_WIDTH, { duration: 250 });
        dragX.value = withTiming(0, { duration: 250 });
      } else if (event.translationY > DISMISS_THRESHOLD) {
        // Dismiss on swipe down
        runOnJS(handleClose)();
      } else {
        translateY.value = withSpring(0);
        dragX.value = withSpring(0);
      }
    });

  const tapGesture = Gesture.Tap().onEnd(() => {
    runOnJS(handleClose)();
  });

  const composedGesture = Gesture.Race(panGesture, tapGesture);

  const animatedCarouselStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: offsetX.value + dragX.value },
      { translateY: translateY.value },
    ],
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
          <Animated.View style={[styles.carouselContainer, animatedCarouselStyle]}>
            {images.map((image, index) => {
              const aspectRatio = image.width / image.height;
              let displayWidth = SCREEN_WIDTH;
              let displayHeight = SCREEN_WIDTH / aspectRatio;

              if (displayHeight > SCREEN_HEIGHT * 0.8) {
                displayHeight = SCREEN_HEIGHT * 0.8;
                displayWidth = displayHeight * aspectRatio;
              }

              return (
                <View key={index} style={styles.imageWrapper}>
                  <Image
                    source={{ uri: image.url }}
                    style={{ width: displayWidth, height: displayHeight }}
                    resizeMode="contain"
                  />
                </View>
              );
            })}
          </Animated.View>
        </GestureDetector>
        {images.length > 1 && (
          <View style={styles.indicatorContainer}>
            {images.map((_, index) => (
              <Indicator
                key={index}
                index={index}
                offsetX={offsetX}
                dragX={dragX}
              />
            ))}
          </View>
        )}
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
  carouselContainer: {
    flexDirection: "row",
    alignItems: "center",
    height: SCREEN_HEIGHT,
  },
  imageWrapper: {
    width: SCREEN_WIDTH,
    justifyContent: "center",
    alignItems: "center",
  },
  indicatorContainer: {
    position: "absolute",
    bottom: 50,
    left: 0,
    right: 0,
    flexDirection: "row",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
  },
  indicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
});
