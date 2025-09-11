import React, { useState } from 'react';
import '@vscode-elements/elements/dist/vscode-collapsible';
import '@vscode-elements/elements/dist/vscode-icon';
import '@vscode-elements/elements/dist/vscode-button';
import { EasyCryptGoal } from '../types';

interface GoalProps {
  goal: EasyCryptGoal;
  isMainGoal?: boolean;
  onToggleOpen?: (goalId: number, isOpen: boolean) => void;
  onToggleContextHidden?: (goalId: number, isContextHidden: boolean) => void;
}

const goalStyles = {
  goal: {
    marginBottom: '16px',
    padding: '12px',
    border: '1px solid var(--vscode-panel-border)',
    borderRadius: '4px',
    backgroundColor: 'var(--vscode-editor-background)'
  },
  mainGoal: {
    borderColor: 'var(--vscode-focusBorder)',
    backgroundColor: 'var(--vscode-editor-selectionBackground)'
  },
  goalHeader: {
    color: 'var(--vscode-textPreformat-foreground)',
    marginBottom: '8px',
    fontSize: '14px'
  },
  hypothesesHeader: {
    color: 'var(--vscode-textLink-foreground)',
    fontWeight: '500',
    marginBottom: '4px',
    fontSize: '13px'
  },
  hypothesis: {
    fontFamily: 'var(--vscode-editor-font-family, "Consolas", monospace)',
    fontSize: '13px',
    color: 'var(--vscode-editor-foreground)',
    marginBottom: '2px',
    paddingLeft: '8px'
  },
  separator: {
    color: 'var(--vscode-panel-border)',
    margin: '8px 0',
    fontFamily: 'monospace'
  },
  conclusion: {
    fontFamily: 'var(--vscode-editor-font-family, "Consolas", monospace)',
    fontSize: '14px',
    color: 'var(--vscode-textPreformat-foreground)',
    padding: '8px',
    backgroundColor: 'var(--vscode-textBlockQuote-background)',
    borderLeft: '3px solid var(--vscode-textBlockQuote-border)',
    marginTop: '8px'
  },
  goalControls: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px'
  },
  goalTitle: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px'
  },
  controlButtons: {
    display: 'flex',
    gap: '4px'
  },
  collapsibleContent: {
    marginTop: '8px'
  }
};

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

  const goalStyle = isMainGoal 
    ? { ...goalStyles.goal, ...goalStyles.mainGoal }
    : goalStyles.goal;

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
    <div style={goalStyle}>
      {/* Goal Controls Header */}
      <div style={goalStyles.goalControls}>
        <div style={goalStyles.goalTitle}>
          <vscode-button
            appearance="icon"
            onClick={handleToggleOpen}
            title={isOpen ? "Collapse goal" : "Expand goal"}
          >
            <vscode-icon name={isOpen ? "chevron-down" : "chevron-right"}></vscode-icon>
          </vscode-button>
          <div style={goalStyles.goalHeader}>
            <strong>Goal {goal.id}</strong>
          </div>
        </div>
        
        <div style={goalStyles.controlButtons}>
          {goal.hypotheses.length > 0 && (
            <vscode-button
              appearance="icon"
              onClick={handleToggleContextHidden}
              title={isContextHidden ? "Show context (hypotheses)" : "Hide context (hypotheses)"}
            >
              <vscode-icon name={isContextHidden ? "eye" : "eye-closed"}></vscode-icon>
            </vscode-button>
          )}
        </div>
      </div>

      {/* Collapsible Content */}
      {isOpen && (
        <vscode-collapsible open={true} style={goalStyles.collapsibleContent}>
          {/* Hypotheses Section */}
          {goal.hypotheses.length > 0 && !isContextHidden && (
            <div>
              <div style={goalStyles.hypothesesHeader}>Hypotheses:</div>
              {goal.hypotheses.map((hyp, index) => (
                <div key={index} style={goalStyles.hypothesis}>
                  {hyp}
                </div>
              ))}
              <div style={goalStyles.separator}>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</div>
            </div>
          )}
          
          {/* Goal Conclusion */}
          <div style={goalStyles.conclusion}>
            <strong>{goal.goal}</strong>
          </div>
        </vscode-collapsible>
      )}
    </div>
  );
};

export default Goal;