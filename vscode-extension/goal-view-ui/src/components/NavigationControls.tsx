import React from 'react';
import '@vscode-elements/elements/dist/vscode-button';
import '@vscode-elements/elements/dist/vscode-icon';
import { ProofNavigation } from '../types';
import styles from './NavigationControls.module.css';

interface NavigationControlsProps {
  navigation: ProofNavigation;
  onStepForward: () => void;
  onStepBackward: () => void;
  onJumpToStep: (step: number) => void;
}

// Styles moved to CSS Module

const NavigationControls: React.FC<NavigationControlsProps> = ({
  navigation,
  onStepForward,
  onStepBackward,
  onJumpToStep
}) => {
  const progressPercentage = (navigation.current_step / navigation.total_steps) * 100;

  const formatTimestamp = (timestamp: number) => {
    const date = new Date(timestamp * 1000);
    return date.toLocaleTimeString();
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div className={styles.title}>Proof Navigation</div>
        <div className={styles.stepInfo}>
          Step {navigation.current_step} of {navigation.total_steps}
        </div>
      </div>

      <div className={styles.controls}>
        <vscode-button
          appearance="secondary"
          onClick={onStepBackward}
          disabled={!navigation.can_step_backward}
          aria-label="Step backward"
        >
          <vscode-icon name="arrow-left"></vscode-icon>
          Previous
        </vscode-button>
        
        <vscode-button
          appearance="primary"
          onClick={onStepForward}
          disabled={!navigation.can_step_forward}
          aria-label="Step forward"
        >
          Next
          <vscode-icon name="arrow-right"></vscode-icon>
        </vscode-button>

        <div className={styles.progressContainer}>
          <div className={styles.progressBar}>
            <div 
              className={styles.progressFill}
              style={{ width: `${progressPercentage}%` }}
            />
          </div>
          <span className={styles.stepText}>{Math.round(progressPercentage)}%</span>
        </div>
      </div>

      {navigation.step_history.length > 0 && (
        <div className={styles.history}>
          <div className={styles.stepText} style={{ marginBottom: '4px' }}>
            Step History
          </div>
          {navigation.step_history.map((step) => (
            <div
              key={step.step_id}
              className={`${styles.historyItem} ${step.step_id === navigation.current_step ? styles.current : ''}`}
              onClick={() => onJumpToStep(step.step_id)}
            >
              <span className={styles.command}>
                {step.step_id}. {step.command}
              </span>
              <span className={styles.timestamp}>
                {formatTimestamp(step.timestamp)}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default NavigationControls;