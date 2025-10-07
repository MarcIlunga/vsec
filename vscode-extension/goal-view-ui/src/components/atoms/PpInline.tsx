import React from 'react';
import './EasyCryptPp.module.css'; // VSCoq-style CSS for syntax highlighting

export interface PpAtom {
  text: string;
  cls?: string | null;
}

export type Pp = PpAtom[];

interface PpInlineProps {
  pp: Pp;
  className?: string;
}

const PpInline: React.FC<PpInlineProps> = ({ pp, className }) => {
  return (
    <span className={className}>
      {pp && pp.length > 0 ? pp.map((a, idx) => (
        <span key={idx} className={a.cls || undefined}>{a.text}</span>
      )) : null}
    </span>
  );
};

export default PpInline;
