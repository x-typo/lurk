import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SubredditFeed } from '../components/SubredditFeed';
import { useSubreddits } from '../context/SubredditContext';
import { colors } from '../constants/colors';

interface SubredditsProps {
  resetKey?: number;
}

export function Subreddits({ resetKey }: SubredditsProps) {
  const [activeSubreddit, setActiveSubreddit] = useState<string | null>(null);
  const [newSub, setNewSub] = useState('');
  const { subreddits, addSubreddit, removeSubreddit } = useSubreddits();

  useEffect(() => {
    setActiveSubreddit(null);
  }, [resetKey]);

  const handleBack = useCallback(() => {
    setActiveSubreddit(null);
  }, []);

  const handleAdd = useCallback(() => {
    const name = newSub.trim();
    if (!name) return;
    addSubreddit(name);
    setNewSub('');
  }, [newSub, addSubreddit]);

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
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView contentContainerStyle={styles.pickerContent}>
        <View style={styles.addRow}>
          <TextInput
            style={styles.input}
            value={newSub}
            onChangeText={setNewSub}
            placeholder="Add subreddit..."
            placeholderTextColor={colors.textMuted}
            onSubmitEditing={handleAdd}
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="done"
          />
          <TouchableOpacity style={styles.addButton} onPress={handleAdd}>
            <Text style={styles.addButtonText}>+</Text>
          </TouchableOpacity>
        </View>

        {subreddits.map((sub) => (
          <View key={sub} style={styles.subRow}>
            <TouchableOpacity
              style={styles.subButton}
              onPress={() => setActiveSubreddit(sub)}
              activeOpacity={0.7}
            >
              <Text style={styles.buttonText}>r/{sub}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.removeButton}
              onPress={() => removeSubreddit(sub)}
            >
              <Text style={styles.removeText}>✕</Text>
            </TouchableOpacity>
          </View>
        ))}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  pickerContent: {
    padding: 20,
    gap: 12,
  },
  addRow: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 8,
  },
  input: {
    flex: 1,
    backgroundColor: colors.surface,
    color: colors.text,
    fontSize: 16,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  addButton: {
    backgroundColor: colors.primary,
    width: 50,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addButtonText: {
    color: colors.text,
    fontSize: 24,
    fontWeight: '700',
  },
  subRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  subButton: {
    flex: 1,
    backgroundColor: colors.surface,
    paddingVertical: 18,
    paddingHorizontal: 20,
    borderRadius: 12,
  },
  buttonText: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
  },
  removeButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceElevated,
    justifyContent: 'center',
    alignItems: 'center',
  },
  removeText: {
    color: colors.textSecondary,
    fontSize: 16,
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
