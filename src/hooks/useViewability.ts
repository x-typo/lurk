import { useRef } from 'react';
import { ViewToken } from 'react-native';
import { RedditPost } from '../types/reddit';

export function useViewability(onSeen: (ids: string[]) => void) {
  const viewabilityConfig = useRef({ viewAreaCoveragePercentThreshold: 50 }).current;

  // FlatList requires stable references for viewability callbacks.
  // onSeen (markSeen) has stable identity (empty dep chain) so the ref never goes stale.
  const onViewableItemsChanged = useRef(
    ({ viewableItems }: { viewableItems: ViewToken[] }) => {
      const ids = viewableItems
        .filter((item) => item.isViewable)
        .map((item) => (item.item as RedditPost).id);
      if (ids.length > 0) onSeen(ids);
    },
  ).current;

  return { viewabilityConfig, onViewableItemsChanged };
}
