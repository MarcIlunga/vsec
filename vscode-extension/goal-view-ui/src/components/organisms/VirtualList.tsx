import React, { useRef, useState, useEffect, useMemo } from 'react';

interface VirtualListProps<T> {
  items: T[];
  estimatedItemHeight: number;
  overscan?: number;
  renderItem: (item: T, index: number) => React.ReactNode;
  style?: React.CSSProperties;
}

function VirtualList<T>({ items, estimatedItemHeight, overscan = 4, renderItem, style }: VirtualListProps<T>) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [height, setHeight] = useState(400);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const onScroll = () => setScrollTop(el.scrollTop);
    const resizeObserver = new ResizeObserver(() => setHeight(el.clientHeight));
    el.addEventListener('scroll', onScroll, { passive: true });
    resizeObserver.observe(el);
    setHeight(el.clientHeight);
    return () => {
      el.removeEventListener('scroll', onScroll);
      resizeObserver.disconnect();
    };
  }, []);

  const totalHeight = items.length * estimatedItemHeight;
  const startIndex = Math.max(0, Math.floor(scrollTop / estimatedItemHeight) - overscan);
  const endIndex = Math.min(items.length, Math.ceil((scrollTop + height) / estimatedItemHeight) + overscan);
  const visibleItems = useMemo(() => items.slice(startIndex, endIndex), [items, startIndex, endIndex]);
  const topSpacer = startIndex * estimatedItemHeight;

  return (
    <div ref={containerRef} style={{ overflowY: 'auto', maxHeight: 'calc(100vh - 280px)', ...style }}>
      <div style={{ height: totalHeight, position: 'relative' }}>
        <div style={{ position: 'absolute', top: topSpacer, left: 0, right: 0 }}>
          {visibleItems.map((item, i) => {
            const index = startIndex + i;
            return (
              <div key={index} style={{ minHeight: estimatedItemHeight }}>
                {renderItem(item, index)}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default VirtualList;


