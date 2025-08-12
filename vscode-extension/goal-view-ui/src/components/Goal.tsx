import React from 'react';
import { EasyCryptGoal } from '../types';

interface GoalProps {
  goal: EasyCryptGoal;
  isMainGoal?: boolean;
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
  }
};

const Goal: React.FC<GoalProps> = ({ goal, isMainGoal = false }) => {
  const goalStyle = isMainGoal 
    ? { ...goalStyles.goal, ...goalStyles.mainGoal }
    : goalStyles.goal;

  return (
    <div style={goalStyle}>
      <div style={goalStyles.goalHeader}>
        <strong>Goal {goal.id}:</strong>
      </div>
      
      {goal.hypotheses.length > 0 && (
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
      
      <div style={goalStyles.conclusion}>
        <strong>{goal.goal}</strong>
      </div>
    </div>
  );
};

export default Goal;