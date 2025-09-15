import React from 'react';
import Hypothesis from '../atoms/Hypothesis';
import styles from './HypothesesBlock.module.css';

interface HypothesesBlockProps {
  hypotheses: string[];
}

const HypothesesBlock: React.FC<HypothesesBlockProps> = ({ hypotheses }) => {
  if (!hypotheses || hypotheses.length === 0) return null;
  return (
    <ul className={styles.block}>
      {hypotheses.map((h, i) => (
        <Hypothesis key={i} content={h} />
      ))}
    </ul>
  );
};

export default HypothesesBlock;


