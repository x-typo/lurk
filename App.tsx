import React, { useState, useCallback, useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { TopTabBar } from './src/components/TopTabBar';
import { Popular } from './src/screens/Popular';
import { Subreddits } from './src/screens/Subreddits';
import { colors } from './src/constants/colors';

const TABS = [
  { key: 'popular', label: 'Popular' },
  { key: 'subreddits', label: 'Subreddits' },
];

export default function App() {
  const [activeTab, setActiveTab] = useState('popular');
  const [subredditsResetKey, setSubredditsResetKey] = useState(0);

  const handleTabPress = useCallback((key: string) => {
    if (key === 'subreddits' && activeTab === 'subreddits') {
      // Tapping Subreddits while already on it → reset to picker
      setSubredditsResetKey((prev) => prev + 1);
    }
    setActiveTab(key);
  }, [activeTab]);

  const content = useMemo(() => {
    switch (activeTab) {
      case 'popular':
        return <Popular />;
      case 'subreddits':
        return <Subreddits resetKey={subredditsResetKey} />;
      default:
        return null;
    }
  }, [activeTab, subredditsResetKey]);

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
          <View style={styles.content}>{content}</View>
          <TopTabBar tabs={TABS} activeTab={activeTab} onTabPress={handleTabPress} />
        </SafeAreaView>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
});
