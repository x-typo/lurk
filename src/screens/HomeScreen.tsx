import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors } from '../constants/colors';

export function HomeScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.text}>Sign in to see your home feed</Text>
      <Text style={styles.subtext}>
        Your subscribed subreddits will appear here
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
    padding: 20,
  },
  text: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
  subtext: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
});
