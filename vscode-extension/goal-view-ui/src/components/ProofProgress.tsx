import React from 'react';
import styles from './ProofProgress.module.css';

interface ProofProgressProps {
  progress: number; // 0.0 to 1.0
  currentLemma?: string;
  totalGoals?: number;
  completedGoals?: number;
}

// Styles moved to CSS Module

const ProofProgress: React.FC<ProofProgressProps> = ({
  progress,
  currentLemma,
  totalGoals,
  completedGoals
}) => {
  const percentage = Math.round(progress * 100);
  
  const getStatusBadge = () => {
    if (progress >= 1.0) {
      return (
        <span className={`${styles.badge} ${styles.badgeComplete}`}>
          Complete
        </span>
      );
    } else if (progress > 0) {
      return (
        <span className={`${styles.badge} ${styles.badgeInProgress}`}>
          In Progress
        </span>
      );
    } else {
      return (
        <span className={`${styles.badge} ${styles.badgeIdle}`}>
          Not Started
        </span>
      );
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div className={styles.lemmaTitle}>
          {currentLemma || 'Unnamed Proof'}
        </div>
        <div className={styles.stats}>
          {typeof totalGoals === 'number' && typeof completedGoals === 'number' 
            ? `${completedGoals}/${totalGoals} goals • `
            : ''}{getStatusBadge()}
        </div>
      </div>

      <div className={styles.progressBarContainer}>
        <div className={styles.progressBar}>
          <div
            className={styles.progressFill}
            style={{ width: `${percentage}%` }}
          />
        </div>
        
        <span className={styles.progressText}>
          {percentage}%
        </span>
      </div>
    </div>
  );
};

export default ProofProgress;