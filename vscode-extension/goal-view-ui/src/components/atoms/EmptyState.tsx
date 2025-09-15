import React from 'react';
import styles from './EmptyState.module.css';

interface EmptyStateProps {
  message: string;
  hint?: string;
}

const EmptyState: React.FC<EmptyStateProps> = ({ message, hint }) => {
  return (
    <div className={styles.root}>
      <div>{message}</div>
      {hint && <div className={styles.hint}>{hint}</div>}
    </div>
  );
};

export default EmptyState;


