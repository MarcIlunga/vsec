import React from 'react';

export default function ProgressBar({ value }: { value?: number }) {
  const pct = typeof value === 'number' && !Number.isNaN(value) ? Math.max(0, Math.min(1, value)) : 0;
  const percent = Math.round(pct * 100);
  return (
    <div style={{ width: '100%', height: 6, background: 'var(--vscode-editorWidget-border)', borderRadius: 3, overflow: 'hidden' }}>
      <div style={{ width: `${percent}%`, height: '100%', background: 'var(--vscode-editorInfo-foreground)', transition: 'width 120ms ease-out' }} />
    </div>
  );
}
