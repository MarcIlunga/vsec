import React from 'react';
import { ProofNavigation } from '../types';

interface NavigationControlsProps {
  navigation: ProofNavigation;
  onStepForward: () => void;
  onStepBackward: () => void;
  onJumpToStep: (step: number) => void;
}

const navStyles = {
  container: {
    padding: '12px',
    borderBottom: '1px solid var(--vscode-panel-border)',
    backgroundColor: 'var(--vscode-editor-inactiveSelectionBackground)',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  title: {
    color: 'var(--vscode-textPreformat-foreground)',
    fontWeight: 'bold' as const,
    fontSize: '14px',
  },
  stepInfo: {
    color: 'var(--vscode-descriptionForeground)',
    fontSize: '12px',
  },
  controls: {
    display: 'flex',
    gap: '8px',
    alignItems: 'center',
    marginBottom: '8px',
  },
  button: {
    background: 'var(--vscode-button-background)',
    color: 'var(--vscode-button-foreground)',
    border: 'none',
    padding: '4px 8px',
    borderRadius: '3px',
    cursor: 'pointer',
    fontSize: '12px',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  buttonDisabled: {
    background: 'var(--vscode-button-secondaryBackground)',
    color: 'var(--vscode-button-secondaryForeground)',
    cursor: 'not-allowed',
    opacity: 0.6,
  },
  progressContainer: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  progressBar: {
    flex: 1,
    height: '6px',
    backgroundColor: 'var(--vscode-progressBar-background)',
    borderRadius: '3px',
    overflow: 'hidden' as const,
  },
  progressFill: {
    height: '100%',
    backgroundColor: 'var(--vscode-progressBar-color)',
    transition: 'width 0.3s ease',
  },
  stepText: {
    color: 'var(--vscode-textPreformat-foreground)',
    fontSize: '11px',
    fontFamily: 'var(--vscode-editor-font-family, monospace)',
  },
  history: {
    marginTop: '8px',
    maxHeight: '120px',
    overflowY: 'auto' as const,
  },
  historyItem: {
    display: 'flex',
    justifyContent: 'space-between',
    padding: '2px 4px',
    fontSize: '11px',
    color: 'var(--vscode-editor-foreground)',
    borderRadius: '2px',
    cursor: 'pointer',
  },
  historyItemCurrent: {
    backgroundColor: 'var(--vscode-list-activeSelectionBackground)',
    color: 'var(--vscode-list-activeSelectionForeground)',
  },
  historyItemHover: {
    backgroundColor: 'var(--vscode-list-hoverBackground)',
  },
  command: {
    fontFamily: 'var(--vscode-editor-font-family, monospace)',
    color: 'var(--vscode-textLink-foreground)',
  },
  timestamp: {
    color: 'var(--vscode-descriptionForeground)',
  }
};

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
    <div style={navStyles.container}>
      <div style={navStyles.header}>
        <div style={navStyles.title}>🎯 Proof Navigation</div>
        <div style={navStyles.stepInfo}>
          Step {navigation.current_step} of {navigation.total_steps}
        </div>
      </div>

      <div style={navStyles.controls}>
        <button
          style={{
            ...navStyles.button,
            ...(navigation.can_step_backward ? {} : navStyles.buttonDisabled)
          }}
          onClick={onStepBackward}
          disabled={!navigation.can_step_backward}
        >
          ⬅️ Previous
        </button>
        
        <button
          style={{
            ...navStyles.button,
            ...(navigation.can_step_forward ? {} : navStyles.buttonDisabled)
          }}
          onClick={onStepForward}
          disabled={!navigation.can_step_forward}
        >
          Next ➡️
        </button>

        <div style={navStyles.progressContainer}>
          <div style={navStyles.progressBar}>
            <div 
              style={{
                ...navStyles.progressFill,
                width: `${progressPercentage}%`
              }}
            />
          </div>
          <span style={navStyles.stepText}>{Math.round(progressPercentage)}%</span>
        </div>
      </div>

      {navigation.step_history.length > 0 && (
        <div style={navStyles.history}>
          <div style={{ ...navStyles.stepText, marginBottom: '4px' }}>
            📜 Step History:
          </div>
          {navigation.step_history.map((step) => (
            <div
              key={step.step_id}
              style={{
                ...navStyles.historyItem,
                ...(step.step_id === navigation.current_step ? navStyles.historyItemCurrent : {})
              }}
              onClick={() => onJumpToStep(step.step_id)}
              onMouseEnter={(e) => {
                if (step.step_id !== navigation.current_step) {
                  Object.assign(e.currentTarget.style, navStyles.historyItemHover);
                }
              }}
              onMouseLeave={(e) => {
                if (step.step_id !== navigation.current_step) {
                  e.currentTarget.style.backgroundColor = 'transparent';
                }
              }}
            >
              <span style={navStyles.command}>
                {step.step_id}. {step.command}
              </span>
              <span style={navStyles.timestamp}>
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