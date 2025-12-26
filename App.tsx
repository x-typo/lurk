import React, { useState, useCallback, useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { TopTabBar } from './src/components/TopTabBar';
import { PopularScreen } from './src/screens/PopularScreen';
import { HomeScreen } from './src/screens/HomeScreen';
import { colors } from './src/constants/colors';

const TABS = [
  { key: 'popular', label: 'Popular' },
  { key: 'home', label: 'Home' },
];

export default function App() {
  const [activeTab, setActiveTab] = useState('popular');

  const handleTabPress = useCallback((key: string) => {
    setActiveTab(key);
  }, []);

  const content = useMemo(() => {
    switch (activeTab) {
      case 'popular':
        return <PopularScreen />;
      case 'home':
        return <HomeScreen />;
      default:
        return null;
    }
  }, [activeTab]);

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
        <View style={styles.content}>{content}</View>
        <TopTabBar tabs={TABS} activeTab={activeTab} onTabPress={handleTabPress} />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
});
