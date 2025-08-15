import React, { useEffect, useState } from 'react';
import ProgressBar from './components/atoms/ProgressBar';
import ProofViewPage from './components/templates/ProofViewPage';
import { CollapsibleGoal, ProofViewGoals, ProofViewGoalsKey, ProofViewMessage } from './types';

export default function App() {
  const [progress, setProgress] = useState<number | undefined>(undefined);
  const [remaining, setRemaining] = useState<number | undefined>(undefined);
  const [noGoals, setNoGoals] = useState<boolean>(false);
  const [goals, setGoals] = useState<ProofViewGoals>(null);
  const [messages, setMessages] = useState<ProofViewMessage[]>([]);
  const [displaySetting] = useState<string>('smart-expand');
  const [maxDepth] = useState<number>(2);
  const [helpMessage, setHelpMessage] = useState<string>('');

  useEffect(() => {
    const handler = (event: MessageEvent) => {
      const msg: any = event.data || {};
      if (msg && msg.command === 'renderProofView' && msg.proofView) {
        if (typeof msg.proofView.progress === 'number') {
          setProgress(msg.proofView.progress);
        }
        const proof = msg.proofView.proof;
        if (proof && typeof proof.remaining === 'number') {
          setRemaining(proof.remaining);
          setNoGoals(proof.remaining === 0);
        } else {
          setRemaining(undefined);
          setNoGoals(false);
        }

        // Map proof.goals to ProofViewGoals for rendering
        if (proof && Array.isArray(proof.goals)) {
          const toCollapsible = (g: any): CollapsibleGoal => ({
            id: String(g.id ?? ''),
            goal: g.goal ?? '',
            hypotheses: Array.isArray(g.hypotheses) ? g.hypotheses : [],
            isOpen: true,
            isContextHidden: false,
          });
          const main = proof.goals.map(toCollapsible);
          const shelved = Array.isArray(proof.shelvedGoals) ? proof.shelvedGoals.map(toCollapsible) : [];
          const givenUp = Array.isArray(proof.givenUpGoals) ? proof.givenUpGoals.map(toCollapsible) : [];
          const unfocused = Array.isArray(proof.unfocusedGoals) ? proof.unfocusedGoals.map(toCollapsible) : [];
          setGoals({ main, shelved, givenUp, unfocused });
        } else {
          setGoals({ main: [], shelved: [], givenUp: [], unfocused: [] });
        }

        const msgs = Array.isArray(msg.proofView.messages) ? msg.proofView.messages : [];
        setMessages(msgs);
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '6px 8px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <ProgressBar value={progress} />
        {typeof remaining === 'number' && remaining >= 0 && (
          <span style={{ fontSize: 11, opacity: 0.8 }} title="Remaining goals">{remaining}</span>
        )}
        {noGoals && (
          <span style={{ fontSize: 11, opacity: 0.8 }} title="No more goals">No more goals</span>
        )}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflow: 'auto' }}>
        <ProofViewPage
          goals={goals}
          messages={messages}
          collapseGoalHandler={(id: string, _key: ProofViewGoalsKey) => void id}
          toggleContextHandler={(id: string, _key: ProofViewGoalsKey) => void id}
          displaySetting={displaySetting}
          maxDepth={maxDepth}
          settingsClickHandler={() => {}}
          helpMessage={helpMessage}
          helpMessageHandler={setHelpMessage}
          showError={true}
          showWarning={true}
          showInfo={true}
          showHint={true}
          onFilterChange={() => {}}
        />
      </div>
    </div>
  );
}