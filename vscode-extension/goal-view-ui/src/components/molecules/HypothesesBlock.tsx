import React from 'react';
import Hypothesis from '../atoms/Hypothesis';
import PpInline from '../atoms/PpInline';
import styles from './HypothesesBlock.module.css';

interface HypothesesBlockProps {
  hypotheses: string[];
  hypotheses_pp?: { text: string; cls?: string | null }[][];
}

const HypothesesBlock: React.FC<HypothesesBlockProps> = ({ hypotheses, hypotheses_pp }) => {
  const hasPp = Array.isArray(hypotheses_pp) && hypotheses_pp!.length === hypotheses.length;
  if ((!hypotheses || hypotheses.length === 0) && !hasPp) return null;
  return (
    <ul className={styles.block}>
      {hasPp
        ? hypotheses_pp!.map((pp, i) => (
            <li key={i} className={styles.item}><PpInline pp={pp} /></li>
          ))
        : hypotheses.map((h, i) => (
            <Hypothesis key={i} content={h} />
          ))}
    </ul>
  );
};

export default HypothesesBlock;


