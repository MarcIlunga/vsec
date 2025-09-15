import React from 'react';
import HypothesesBlock from './HypothesesBlock';
import styles from './GoalBlock.module.css';
import PpRenderer from '../atoms/PpRenderer';
import MinimalButton from '../atoms/MinimalButton';
import { VscCopy } from 'react-icons/vsc';

interface GoalBlockProps {
  id?: number;
  index?: number;
  count?: number;
  hypotheses: string[];
  goal: string;
  isContextHidden?: boolean;
}

const GoalBlock: React.FC<GoalBlockProps> = ({ 
  id, 
  index, 
  count, 
  hypotheses, 
  goal, 
  isContextHidden = false
}) => {
  const indicator = typeof index === 'number' && typeof count === 'number' ? `(${index + 1} / ${count})` : undefined;
  
  return (
    <div className={styles.block} data-goal-id={id}>
      {!isContextHidden && <HypothesesBlock hypotheses={hypotheses} />}
      <div className={styles.separatorZone}>
        {indicator && <span className={styles.goalIndex}>{indicator}</span>}
        <div className={styles.separator} />
      </div>
      <div className={styles.conclusionRow}>
        <div className={styles.conclusionText}><strong><PpRenderer content={goal} /></strong></div>
        <MinimalButton 
          title="Copy goal text to clipboard" 
          ariaLabel="Copy goal text to clipboard" 
          className={styles.copyButton}
          onClick={() => {
            navigator.clipboard.writeText(goal);
            // Optional: Add visual feedback for copy success
          }}
        >
          <VscCopy />
        </MinimalButton>
      </div>
    </div>
  );
};

export default GoalBlock;


