import React from 'react';
import styles from './EmptyState.module.css';

interface EmptyStateProps {
  message: string;
  hint?: string;
  icon?: React.ReactNode;
}

const EmptyState: React.FC<EmptyStateProps> = ({ message, hint, icon }) => {
  const defaultHint = 'Open a proof and step forward to see current goals.';
  return (
    <div className={styles.root}>
      {icon && <div className={styles.icon}>{icon}</div>}
      <div>{message}</div>
      <div className={styles.hint}>{hint || defaultHint}</div>
    </div>
  );
};

export default EmptyState;


