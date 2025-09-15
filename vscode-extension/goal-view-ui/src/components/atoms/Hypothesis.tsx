import React from 'react';
import styles from './Hypothesis.module.css';

interface HypothesisProps {
  content: string;
}

const Hypothesis: React.FC<HypothesisProps> = ({ content }) => {
  return (
    <li className={styles.item}>{content}</li>
  );
};

export default Hypothesis;


