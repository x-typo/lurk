import React, { createContext, useContext, useState, useEffect, useCallback, useMemo } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = 'lurk:subreddits';
const DEFAULT_SUBS = ['ClaudeAI', 'ClaudeCode', 'singularity'];

interface SubredditContextType {
  subreddits: string[];
  addSubreddit: (name: string) => void;
  removeSubreddit: (name: string) => void;
  loaded: boolean;
}

const SubredditContext = createContext<SubredditContextType | null>(null);

export function SubredditProvider({ children }: { children: React.ReactNode }) {
  const [subreddits, setSubreddits] = useState<string[]>(DEFAULT_SUBS);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((data) => {
        if (data) {
          try {
            setSubreddits(JSON.parse(data));
          } catch {
            // Corrupted data - keep defaults
          }
        }
        setLoaded(true);
      })
      .catch(() => setLoaded(true));
  }, []);

  const persist = useCallback((subs: string[]) => {
    AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(subs));
  }, []);

  const addSubreddit = useCallback(
    (name: string) => {
      const normalized = name.replace(/^r\//, '').trim();
      if (!normalized) return;

      setSubreddits((prev) => {
        if (prev.some((s) => s.toLowerCase() === normalized.toLowerCase())) return prev;
        const next = [...prev, normalized];
        persist(next);
        return next;
      });
    },
    [persist],
  );

  const removeSubreddit = useCallback(
    (name: string) => {
      setSubreddits((prev) => {
        const next = prev.filter((s) => s !== name);
        persist(next);
        return next;
      });
    },
    [persist],
  );

  const value = useMemo(
    () => ({ subreddits, addSubreddit, removeSubreddit, loaded }),
    [subreddits, addSubreddit, removeSubreddit, loaded],
  );

  return <SubredditContext.Provider value={value}>{children}</SubredditContext.Provider>;
}

export function useSubreddits() {
  const ctx = useContext(SubredditContext);
  if (!ctx) throw new Error('useSubreddits must be used within SubredditProvider');
  return ctx;
}
