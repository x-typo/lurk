import React, { createContext, useContext, useState, useEffect, useCallback, useRef, useMemo } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = 'lurk:hidden_posts';
const MAX_ENTRIES = 5000;

interface PostFilterContextType {
  hidePost: (id: string) => void;
  markSeen: (ids: string[]) => void;
  isHidden: (id: string) => boolean;
  clearAll: () => void;
  loaded: boolean;
}

const PostFilterContext = createContext<PostFilterContextType | null>(null);

export function PostFilterProvider({ children }: { children: React.ReactNode }) {
  const [loaded, setLoaded] = useState(false);
  const idsRef = useRef<string[]>([]);
  const setRef = useRef<Set<string>>(new Set());
  const persistTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((data) => {
        if (data) {
          try {
            const stored = JSON.parse(data) as string[];
            // Merge with any IDs added before load completed
            const merged = [...new Set([...stored, ...idsRef.current])];
            idsRef.current = merged.slice(-MAX_ENTRIES);
            setRef.current = new Set(idsRef.current);
          } catch {
            // Corrupted data - start fresh
            idsRef.current = [];
            setRef.current = new Set();
          }
        }
        setLoaded(true);
      })
      .catch(() => setLoaded(true));
  }, []);

  const persistDebounced = useCallback(() => {
    if (persistTimeout.current) clearTimeout(persistTimeout.current);
    persistTimeout.current = setTimeout(() => {
      AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(idsRef.current));
    }, 1000);
  }, []);

  const addIds = useCallback(
    (ids: string[]) => {
      const newIds = ids.filter((id) => !setRef.current.has(id));
      if (newIds.length === 0) return;
      for (const id of newIds) {
        setRef.current.add(id);
        idsRef.current.push(id);
      }
      if (idsRef.current.length > MAX_ENTRIES) {
        idsRef.current = idsRef.current.slice(-MAX_ENTRIES);
        setRef.current = new Set(idsRef.current);
      }
      persistDebounced();
    },
    [persistDebounced],
  );

  const hidePost = useCallback((id: string) => addIds([id]), [addIds]);
  const markSeen = useCallback((ids: string[]) => addIds(ids), [addIds]);
  const isHidden = useCallback((id: string) => setRef.current.has(id), []);

  const clearAll = useCallback(() => {
    idsRef.current = [];
    setRef.current = new Set();
    AsyncStorage.removeItem(STORAGE_KEY);
  }, []);

  const value = useMemo(
    () => ({ hidePost, markSeen, isHidden, clearAll, loaded }),
    [hidePost, markSeen, isHidden, clearAll, loaded],
  );

  return <PostFilterContext.Provider value={value}>{children}</PostFilterContext.Provider>;
}

export function usePostFilter() {
  const ctx = useContext(PostFilterContext);
  if (!ctx) throw new Error('usePostFilter must be used within PostFilterProvider');
  return ctx;
}
