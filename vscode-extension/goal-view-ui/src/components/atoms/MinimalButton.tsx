import React from 'react';
import styles from './MinimalButton.module.css';

interface MinimalButtonProps {
  onClick?: (params?: any) => void;
  ariaLabel?: string;
  title?: string;
  children: React.ReactNode;
  className?: string;
}

const MinimalButton: React.FC<MinimalButtonProps> = ({ 
  onClick, 
  ariaLabel, 
  title,
  children, 
  className = '' 
}) => {
  return (
    <button
      className={`${styles.minimalButton} ${className}`}
      onClick={onClick}
      aria-label={ariaLabel}
      title={title}
      type="button"
    >
      {children}
    </button>
  );
};

export default MinimalButton;
