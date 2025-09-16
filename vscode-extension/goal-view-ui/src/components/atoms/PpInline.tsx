import React from 'react';

export interface PpAtom {
  text: string;
  cls?: string | null;
}

export type Pp = PpAtom[];

interface PpInlineProps {
  pp: Pp;
  className?: string;
}

const tokenStyleFor = (cls?: string | null): React.CSSProperties => {
  if (!cls) return {};
  const c = cls.toLowerCase();
  const cs = getComputedStyle(document.documentElement);
  switch (c) {
    case 'keyword':
      return { color: cs.getPropertyValue('--vscode-textLink-foreground') || undefined };
    case 'ident':
    case 'variable':
      return { color: cs.getPropertyValue('--vscode-editor-foreground') || undefined };
    case 'type':
      return { color: cs.getPropertyValue('--vscode-symbolIcon-classForeground') || cs.getPropertyValue('--vscode-textPreformat-foreground') || undefined };
    case 'comment':
      return { color: cs.getPropertyValue('--vscode-textPreformat-foreground') || undefined, fontStyle: 'italic' };
    case 'tactic':
      return { color: cs.getPropertyValue('--vscode-symbolIcon-functionForeground') || undefined };
    case 'module':
    case 'theory':
      return { color: cs.getPropertyValue('--vscode-symbolIcon-namespaceForeground') || undefined };
    default:
      return {};
  }
};

const PpInline: React.FC<PpInlineProps> = ({ pp, className }) => {
  return (
    <span className={className}>
      {pp && pp.length > 0 ? pp.map((a, idx) => (
        <span key={idx} style={tokenStyleFor(a.cls)}>{a.text}</span>
      )) : null}
    </span>
  );
};

export default PpInline;
