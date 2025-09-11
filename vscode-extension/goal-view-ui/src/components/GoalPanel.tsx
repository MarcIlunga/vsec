import React, { useState, useEffect } from 'react';
import '@vscode-elements/elements/dist/vscode-badge';
import '@vscode-elements/elements/dist/vscode-tabs';
import '@vscode-elements/elements/dist/vscode-tab-header';
import '@vscode-elements/elements/dist/vscode-tab-panel';
import { EasyCryptProofState, ProofViewMessage } from '../types';
import Goal from './Goal';
import NavigationControls from './NavigationControls';
import ProofProgress from './ProofProgress';

const panelStyles = {
  goalPanel: {
    padding: '16px',
    height: '100vh',
    overflowY: 'auto' as const
  },
  headerH2: {
    color: 'var(--vscode-textPreformat-foreground)',
    margin: '0 0 16px 0',
    fontSize: '18px',
    borderBottom: '1px solid var(--vscode-panel-border)',
    paddingBottom: '8px'
  },
  noProof: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '60%',
    textAlign: 'center' as const
  },
  welcomeMessageH3: {
    color: 'var(--vscode-textLink-foreground)',
    marginBottom: '12px'
  },
  welcomeMessageP: {
    color: 'var(--vscode-descriptionForeground)',
    marginBottom: '20px'
  },
  helpText: {
    textAlign: 'left' as const,
    maxWidth: '400px',
    color: 'var(--vscode-editor-foreground)'
  },
  helpTextUl: {
    listStyleType: 'none' as const,
    paddingLeft: '0'
  },
  helpTextLi: {
    margin: '4px 0'
  },
  helpTextCode: {
    backgroundColor: 'var(--vscode-textPreformat-background)',
    padding: '2px 6px',
    borderRadius: '3px',
    fontFamily: 'var(--vscode-editor-font-family, monospace)'
  },
  tabs: {
    display: 'flex',
    borderBottom: '1px solid var(--vscode-panel-border)',
    marginBottom: '16px'
  },
  tab: {
    background: 'transparent',
    border: 'none',
    padding: '8px 16px',
    color: 'var(--vscode-tab-inactiveForeground)',
    cursor: 'pointer',
    borderBottom: '2px solid transparent',
    fontSize: '14px'
  },
  tabHover: {
    color: 'var(--vscode-tab-activeForeground)',
    backgroundColor: 'var(--vscode-tab-hoverBackground)'
  },
  tabActive: {
    color: 'var(--vscode-tab-activeForeground)',
    borderBottomColor: 'var(--vscode-focusBorder)'
  },
  emptyState: {
    textAlign: 'center' as const,
    color: 'var(--vscode-descriptionForeground)',
    padding: '40px 20px'
  },
  goalsContainer: {
    maxHeight: 'calc(100vh - 200px)',
    overflowY: 'auto' as const
  }
};

const GoalPanel: React.FC = () => {
  const [proofState, setProofState] = useState<EasyCryptProofState | null>(null);

  // Enhanced navigation handlers
  const handleStepForward = () => {
    // Send step forward command to VS Code
    window.parent?.postMessage({
      type: 'command',
      command: 'vsec.stepForward'
    }, '*');
  };

  const handleStepBackward = () => {
    // Send step backward command to VS Code
    window.parent?.postMessage({
      type: 'command', 
      command: 'vsec.stepBackward'
    }, '*');
  };

  const handleJumpToStep = (step: number) => {
    // Send jump to step command to VS Code
    window.parent?.postMessage({
      type: 'command',
      command: 'vsec.jumpToStep',
      args: { step }
    }, '*');
  };

  useEffect(() => {
    const handleMessage = (event: MessageEvent<ProofViewMessage>) => {
      const { data } = event;
      if (data.type === 'proofView') {
        setProofState(data.proofState);
        console.log('EasyCrypt proof state updated:', data.proofState);
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  const renderGoals = (goals: any[], title: string) => {
    if (goals.length === 0) {
      return (
        <div style={panelStyles.emptyState}>
          <p>No {title.toLowerCase()} goals</p>
        </div>
      );
    }

    return (
      <div style={panelStyles.goalsContainer}>
        {goals.map((goal, index) => (
          <Goal 
            key={goal.id || index} 
            goal={goal} 
            isMainGoal={title === 'Main' && index === 0}
          />
        ))}
      </div>
    );
  };


  return (
    <div style={panelStyles.goalPanel}>
      <div>
        <h2 style={panelStyles.headerH2}>🎯 EasyCrypt Interactive Proving</h2>
      </div>

      {/* Show proof progress if available */}
      {proofState && proofState.proof_progress !== undefined && (
        <ProofProgress
          progress={proofState.proof_progress}
          currentLemma={proofState.current_lemma}
          totalGoals={proofState.goals.length + 3} // assume some completed
          completedGoals={3}
        />
      )}

      {/* Show navigation controls if available */}
      {proofState?.navigation && (
        <NavigationControls
          navigation={proofState.navigation}
          onStepForward={handleStepForward}
          onStepBackward={handleStepBackward}
          onJumpToStep={handleJumpToStep}
        />
      )}

      {!proofState ? (
        <div style={panelStyles.noProof}>
          <div>
            <h3 style={panelStyles.welcomeMessageH3}>Welcome to EasyCrypt Interactive Proving!</h3>
            <p style={panelStyles.welcomeMessageP}>Open an EasyCrypt file (.ec) with proof blocks to start interactive proving.</p>
            <div style={panelStyles.helpText}>
              <strong>Keybindings:</strong>
              <ul style={panelStyles.helpTextUl}>
                <li style={panelStyles.helpTextLi}><code style={panelStyles.helpTextCode}>Ctrl+Right</code> - Step forward</li>
                <li style={panelStyles.helpTextLi}><code style={panelStyles.helpTextCode}>Ctrl+Left</code> - Step backward</li>
                <li style={panelStyles.helpTextLi}><code style={panelStyles.helpTextCode}>Ctrl+End</code> - Interpret to cursor</li>
              </ul>
            </div>
          </div>
        </div>
      ) : (
        <>
          <vscode-tabs>
            <vscode-tab-header slot="header">
              <vscode-tab-panel id="main-tab">
                GOALS
                {proofState.goals.length > 0 && (
                  <vscode-badge>{proofState.goals.length}</vscode-badge>
                )}
              </vscode-tab-panel>
              <vscode-tab-panel id="shelved-tab">
                SHELVED
                {proofState.shelvedGoals.length > 0 && (
                  <vscode-badge>{proofState.shelvedGoals.length}</vscode-badge>
                )}
              </vscode-tab-panel>
              <vscode-tab-panel id="unfocused-tab">
                BACKGROUND
                {proofState.unfocusedGoals.length > 0 && (
                  <vscode-badge>{proofState.unfocusedGoals.length}</vscode-badge>
                )}
              </vscode-tab-panel>
            </vscode-tab-header>

            <vscode-tab-panel id="main-view">
              {renderGoals(proofState.goals, 'Main')}
            </vscode-tab-panel>
            <vscode-tab-panel id="shelved-view">
              {renderGoals(proofState.shelvedGoals, 'Shelved')}
            </vscode-tab-panel>
            <vscode-tab-panel id="unfocused-view">
              {renderGoals(proofState.unfocusedGoals, 'Background')}
            </vscode-tab-panel>
          </vscode-tabs>
        </>
      )}

    </div>
  );
};

export default GoalPanel;