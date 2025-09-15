import React, { useState } from 'react';
import '@vscode-elements/elements/dist/vscode-collapsible';
import MinimalButton from './atoms/MinimalButton';
import { VscChevronDown, VscChevronRight, VscEye, VscEyeClosed, VscCopy } from 'react-icons/vsc';
import { EasyCryptGoal } from '../types';
import styles from './Goal.module.css';

interface GoalProps {
  goal: EasyCryptGoal;
  isMainGoal?: boolean;
  onToggleOpen?: (goalId: number, isOpen: boolean) => void;
  onToggleContextHidden?: (goalId: number, isContextHidden: boolean) => void;
}

// Styles moved to CSS Module

const Goal: React.FC<GoalProps> = ({ 
  goal, 
  isMainGoal = false,
  onToggleOpen,
  onToggleContextHidden 
}) => {
  // Use local state if not provided in props, default to open
  const [localIsOpen, setLocalIsOpen] = useState(goal.isOpen ?? true);
  const [localIsContextHidden, setLocalIsContextHidden] = useState(goal.isContextHidden ?? false);
  
  const isOpen = goal.isOpen !== undefined ? goal.isOpen : localIsOpen;
  const isContextHidden = goal.isContextHidden !== undefined ? goal.isContextHidden : localIsContextHidden;

  const containerClassName = isMainGoal 
    ? `${styles.goal} ${styles.mainGoal}`
    : styles.goal;

  const handleToggleOpen = () => {
    const newIsOpen = !isOpen;
    if (onToggleOpen) {
      onToggleOpen(goal.id, newIsOpen);
    } else {
      setLocalIsOpen(newIsOpen);
    }
  };

  const handleToggleContextHidden = () => {
    const newIsContextHidden = !isContextHidden;
    if (onToggleContextHidden) {
      onToggleContextHidden(goal.id, newIsContextHidden);
    } else {
      setLocalIsContextHidden(newIsContextHidden);
    }
  };

  return (
    <div className={containerClassName}>
      {/* Goal Controls Header */}
      <div className={styles.headerRow}>
        <div className={styles.title}>
          <vscode-button
            appearance="icon"
            onClick={handleToggleOpen}
            title={isOpen ? "Collapse goal" : "Expand goal"}
            aria-label={isOpen ? "Collapse goal" : "Expand goal"}
          >
            {isOpen ? <VscChevronDown /> : <VscChevronRight />}
          </vscode-button>
          <div className={styles.goalHeader}>
            <strong>Goal {goal.id}</strong>
          </div>
        </div>
        
        <div className={styles.actions}>
          {goal.hypotheses.length > 0 && (
            <vscode-button
              appearance="icon"
              onClick={handleToggleContextHidden}
              title={isContextHidden ? "Show context (hypotheses)" : "Hide context (hypotheses)"}
              aria-label={isContextHidden ? "Show context (hypotheses)" : "Hide context (hypotheses)"}
            >
              {isContextHidden ? <VscEye /> : <VscEyeClosed />}
            </vscode-button>
          )}
        </div>
      </div>

      {/* Collapsible Content */}
      {isOpen && (
        <vscode-collapsible open={true} className={styles.collapsibleContent}>
          {/* Hypotheses Section */}
          {goal.hypotheses.length > 0 && !isContextHidden && (
            <div>
              <div className={styles.hypothesesHeader}>Hypotheses:</div>
              {goal.hypotheses.map((hyp, index) => (
                <div key={index} className={styles.hypothesis}>
                  {hyp}
                </div>
              ))}
              <div className={styles.separator}>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</div>
            </div>
          )}
          
          {/* Goal Conclusion */}
          <div className={styles.conclusion}>
            <div className={styles.conclusionRow}>
              <strong>{goal.goal}</strong>
              <MinimalButton title="Copy goal" ariaLabel="Copy goal" onClick={() => navigator.clipboard.writeText(goal.goal)}>
                <VscCopy />
              </MinimalButton>
            </div>
          </div>
        </vscode-collapsible>
      )}
    </div>
  );
};

export default Goal;