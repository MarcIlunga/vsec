import React from 'react';

interface ProofProgressProps {
  progress: number; // 0.0 to 1.0
  currentLemma?: string;
  totalGoals: number;
  completedGoals: number;
}

const progressStyles = {
  container: {
    padding: '8px 12px',
    backgroundColor: 'var(--vscode-editor-background)',
    borderBottom: '1px solid var(--vscode-panel-border)',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  lemmaTitle: {
    color: 'var(--vscode-textPreformat-foreground)',
    fontWeight: 'bold' as const,
    fontSize: '13px',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  stats: {
    color: 'var(--vscode-descriptionForeground)',
    fontSize: '11px',
  },
  progressBarContainer: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  progressBar: {
    flex: 1,
    height: '8px',
    backgroundColor: 'var(--vscode-progressBar-background)',
    borderRadius: '4px',
    overflow: 'hidden' as const,
    position: 'relative' as const,
  },
  progressFill: {
    height: '100%',
    borderRadius: '4px',
    transition: 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
    position: 'relative' as const,
  },
  progressText: {
    color: 'var(--vscode-textPreformat-foreground)',
    fontSize: '11px',
    fontWeight: 'bold' as const,
    minWidth: '35px',
    textAlign: 'right' as const,
  },
  statusBadge: {
    padding: '2px 6px',
    borderRadius: '10px',
    fontSize: '10px',
    fontWeight: 'bold' as const,
    textTransform: 'uppercase' as const,
  },
  statusInProgress: {
    backgroundColor: 'var(--vscode-editorWarning-background)',
    color: 'var(--vscode-editorWarning-foreground)',
  },
  statusComplete: {
    backgroundColor: 'var(--vscode-editorInfo-background)',
    color: 'var(--vscode-editorInfo-foreground)',
  },
  statusError: {
    backgroundColor: 'var(--vscode-editorError-background)',
    color: 'var(--vscode-editorError-foreground)',
  }
};

const ProofProgress: React.FC<ProofProgressProps> = ({
  progress,
  currentLemma,
  totalGoals,
  completedGoals
}) => {
  const percentage = Math.round(progress * 100);
  
  // Dynamic color based on progress
  const getProgressColor = () => {
    if (progress < 0.3) return 'var(--vscode-editorError-foreground)';
    if (progress < 0.7) return 'var(--vscode-editorWarning-foreground)';
    return 'var(--vscode-editorInfo-foreground)';
  };

  const getStatusBadge = () => {
    if (progress >= 1.0) {
      return (
        <span style={{...progressStyles.statusBadge, ...progressStyles.statusComplete}}>
          ✅ Complete
        </span>
      );
    } else if (progress > 0) {
      return (
        <span style={{...progressStyles.statusBadge, ...progressStyles.statusInProgress}}>
          🔄 In Progress
        </span>
      );
    } else {
      return (
        <span style={{...progressStyles.statusBadge, ...progressStyles.statusError}}>
          ⭕ Not Started
        </span>
      );
    }
  };

  const getProgressEmoji = () => {
    if (progress >= 1.0) return '🎉';
    if (progress >= 0.8) return '🔥';
    if (progress >= 0.5) return '⚡';
    if (progress >= 0.2) return '🎯';
    return '🏁';
  };

  return (
    <div style={progressStyles.container}>
      <div style={progressStyles.header}>
        <div style={progressStyles.lemmaTitle}>
          {getProgressEmoji()} {currentLemma || 'Unnamed Proof'}
        </div>
        <div style={progressStyles.stats}>
          {completedGoals}/{totalGoals} goals • {getStatusBadge()}
        </div>
      </div>

      <div style={progressStyles.progressBarContainer}>
        <div style={progressStyles.progressBar}>
          <div
            style={{
              ...progressStyles.progressFill,
              width: `${percentage}%`,
              backgroundColor: getProgressColor(),
              boxShadow: progress > 0 ? `0 0 6px ${getProgressColor()}40` : 'none',
            }}
          />
          
          {/* Add sparkle effect for high progress */}
          {progress >= 0.8 && (
            <div style={{
              position: 'absolute',
              top: '1px',
              left: `${percentage - 8}%`,
              width: '6px',
              height: '6px',
              borderRadius: '50%',
              backgroundColor: 'white',
              opacity: 0.8,
              animation: 'pulse 1s infinite'
            }} />
          )}
        </div>
        
        <span style={progressStyles.progressText}>
          {percentage}%
        </span>
      </div>

      <style>
        {`
          @keyframes pulse {
            0%, 100% { opacity: 0.8; transform: scale(1); }
            50% { opacity: 1; transform: scale(1.2); }
          }
        `}
      </style>
    </div>
  );
};

export default ProofProgress;