import React, { useState, useEffect } from 'react';
import styles from './GoalPanel.module.css';
import MinimalButton from './atoms/MinimalButton';
import { VscGear } from 'react-icons/vsc';
import { EasyCryptProofState, ProofViewMessage } from '../types';
import GoalSection from './organisms/GoalSection';
import Message from './atoms/Message';
import Accordion from './atoms/Accordion';
import EmptyState from './atoms/EmptyState';

// Styles moved to CSS Module

const GoalPanel: React.FC = () => {
  const [proofState, setProofState] = useState<EasyCryptProofState | null>(null);
  const [messages, setMessages] = useState<any[] | null>(null);
  const [displayMode, setDisplayMode] = useState<'tabs' | 'list'>('tabs');
  const [settingsOpen, setSettingsOpen] = useState<boolean>(false);
  const [goalStates, setGoalStates] = useState<Map<number, { isOpen: boolean; isContextHidden: boolean }>>(new Map());
  const [prefs, setPrefs] = useState<{ defaultOpen: boolean; defaultContextHidden: boolean }>({ defaultOpen: true, defaultContextHidden: false });

  useEffect(() => {
    const handleMessage = (event: MessageEvent<ProofViewMessage>) => {
      const { data } = event;
      if (data.type === 'proofView') {
        setProofState(data.proofState);
      } else if ((data as any).type === 'messages') {
        setMessages((data as any).messages || []);
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  // Load persisted settings on mount
  useEffect(() => {
    try {
      const vscode = (window as any).acquireVsCodeApi ? (window as any).acquireVsCodeApi() : (window as any).vscode;
      const state = vscode?.getState?.();
      if (state?.goalPrefs) {
        setPrefs(state.goalPrefs);
      }
      if (state?.goalDisplayMode && (state.goalDisplayMode === 'tabs' || state.goalDisplayMode === 'list')) {
        setDisplayMode(state.goalDisplayMode);
      }
    } catch (_) {
      // ignore
    }
  }, []);

  // Persist settings when changed
  useEffect(() => {
    try {
      const vscode = (window as any).acquireVsCodeApi ? (window as any).acquireVsCodeApi() : (window as any).vscode;
      const prev = vscode?.getState?.() || {};
      vscode?.setState?.({ ...prev, goalPrefs: prefs, goalDisplayMode: displayMode });
    } catch (_) {}
  }, [prefs, displayMode]);

  // Goal state management handlers
  const handleToggleGoalOpen = (goalId: number, isOpen: boolean) => {
    setGoalStates(prevStates => {
      const newMap = new Map(prevStates);
      const currentState = newMap.get(goalId) || { isOpen: prefs.defaultOpen, isContextHidden: prefs.defaultContextHidden };
      newMap.set(goalId, { ...currentState, isOpen });
      return newMap;
    });
    // Auto-scroll to goal when opened (like vsrocq)
    if (isOpen) {
      setTimeout(() => {
        const el = document.querySelector(`[data-goal-id="${goalId}"]`);
        if (el && 'scrollIntoView' in el) {
          (el as HTMLElement).scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      }, 0);
    }
  };

  const handleToggleGoalContextHidden = (goalId: number, isContextHidden: boolean) => {
    setGoalStates(prevStates => {
      const newMap = new Map(prevStates);
      const currentState = newMap.get(goalId) || { isOpen: true, isContextHidden: false };
      newMap.set(goalId, { ...currentState, isContextHidden });
      return newMap;
    });
  };

  const settingsClickHandler = () => {
    setSettingsOpen(!settingsOpen);
  };

  return (
    <div className={styles.page}>
      {/* Header with settings button like vsrocq */}
      <div className={styles.buttonContainer}>
        <div className={styles.helpMessage}>
          {/* Help message can go here */}
        </div>
        <MinimalButton 
          title="Open goal panel settings"
          onClick={settingsClickHandler}
          ariaLabel="Open goal panel settings"
          className={settingsOpen ? styles.settingsButtonActive : styles.settingsButton}
        >
          <VscGear />
        </MinimalButton>
      </div>

      {!proofState ? (
        <>
          <EmptyState message="Not in proof mode" hint="Open an EasyCrypt file and start a proof to view goals." />
          {messages && messages.length > 0 && (
            <Accordion title="Messages" collapsed={false}>
              <div className={styles.panel}>
                {messages.map((m, idx) => {
                  const sev = (m.severity || 'info').toLowerCase();
                  return (
                    <Message key={idx} severity={(sev as any) || 'info'} text={m.message} />
                  );
                })}
              </div>
            </Accordion>
          )}
        </>
      ) : (
        <>
          {/* Proof accordion - like vsrocq */}
          <Accordion title="Proof" collapsed={false}>
            {/* Settings panel */}
            {settingsOpen && (
              <div className={styles.settingsPanel}>
                <div className={styles.settingsContent}>
                  <div>
                    <strong>Display mode</strong>
                    <div className={styles.settingsDisplayMode}>
                      <vscode-button appearance={displayMode === 'tabs' ? 'primary' : 'secondary'} onClick={() => setDisplayMode('tabs')}>Tabs</vscode-button>
                      <vscode-button appearance={displayMode === 'list' ? 'primary' : 'secondary'} onClick={() => setDisplayMode('list')}>List</vscode-button>
                    </div>
                  </div>
                    <div>
                      <strong>Goal Display Preferences</strong>
                      <div className={styles.settingsDefaults}>
                        <label className={styles.settingsLabel} title="New goals will start expanded by default">
                          <input type="checkbox" checked={prefs.defaultOpen} onChange={e => setPrefs(prev => ({ ...prev, defaultOpen: (e.target as HTMLInputElement).checked }))} />
                          Goals open by default
                        </label>
                        <label className={styles.settingsLabel} title="New goals will hide hypotheses context by default">
                          <input type="checkbox" checked={prefs.defaultContextHidden} onChange={e => setPrefs(prev => ({ ...prev, defaultContextHidden: (e.target as HTMLInputElement).checked }))} />
                          Hide context by default
                        </label>
                      </div>
                    </div>
                </div>
              </div>
            )}

            <GoalSection
              goals={proofState.goals}
              shelvedGoals={proofState.shelvedGoals}
              unfocusedGoals={proofState.unfocusedGoals}
              givenUpGoals={proofState.givenUpGoals}
              display={displayMode === 'tabs' ? 'Tabs' : 'List'}
              goalStates={goalStates}
              onToggleGoalOpen={handleToggleGoalOpen}
              onToggleGoalContextHidden={handleToggleGoalContextHidden}
              prefs={prefs}
            />
          </Accordion>

          {/* Messages accordion - like vsrocq */}
          {messages && messages.length > 0 && (
            <Accordion title="Messages" collapsed={false}>
              <div className={styles.panel}>
                {messages.map((m, idx) => {
                  const sev = (m.severity || 'info').toLowerCase();
                  return (
                    <Message key={idx} severity={(sev as any) || 'info'} text={m.message} />
                  );
                })}
              </div>
            </Accordion>
          )}
        </>
      )}
    </div>
  );
};

export default GoalPanel;