import React, { useState, useCallback, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Linking } from 'react-native';
import { SubredditFeed } from '../components/SubredditFeed';
import { colors } from '../constants/colors';

const SUBREDDITS = [
  { name: 'r/ClaudeAI', key: 'ClaudeAI' },
  { name: 'r/ClaudeCode', key: 'ClaudeCode' },
  { name: 'r/Codex', key: 'codex' },
  { name: 'r/Singularity', key: 'singularity' },
];

const HOME_URL = 'https://reddit.com/top/?sort=top&t=day';

interface SubredditsProps {
  resetKey?: number;
}

export function Subreddits({ resetKey }: SubredditsProps) {
  const [activeSubreddit, setActiveSubreddit] = useState<string | null>(null);

  // Reset to picker when resetKey changes (tab tapped while already active)
  useEffect(() => {
    setActiveSubreddit(null);
  }, [resetKey]);

  const handleBack = useCallback(() => {
    setActiveSubreddit(null);
  }, []);

  const openHome = useCallback(() => {
    Linking.openURL(HOME_URL);
  }, []);

  if (activeSubreddit) {
    return (
      <View style={styles.container}>
        <TouchableOpacity style={styles.backButton} onPress={handleBack}>
          <Text style={styles.backText}>← r/{activeSubreddit}</Text>
        </TouchableOpacity>
        <SubredditFeed subreddit={activeSubreddit} />
      </View>
    );
  }

  return (
    <View style={styles.pickerContainer}>
      <TouchableOpacity
        style={styles.button}
        onPress={openHome}
        activeOpacity={0.7}
      >
        <Text style={styles.buttonText}>Home</Text>
      </TouchableOpacity>
      {SUBREDDITS.map((sub) => (
        <TouchableOpacity
          key={sub.key}
          style={styles.button}
          onPress={() => setActiveSubreddit(sub.key)}
          activeOpacity={0.7}
        >
          <Text style={styles.buttonText}>{sub.name}</Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  pickerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
    gap: 16,
  },
  button: {
    backgroundColor: colors.primary,
    paddingVertical: 18,
    paddingHorizontal: 32,
    borderRadius: 12,
    minWidth: 200,
    alignItems: 'center',
  },
  buttonText: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '700',
  },
  backButton: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backText: {
    color: colors.primary,
    fontSize: 17,
    fontWeight: '600',
  },
});
