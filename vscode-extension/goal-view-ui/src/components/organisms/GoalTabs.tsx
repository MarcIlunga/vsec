import React, { useState, useRef, useEffect } from 'react';
import CollapsibleGoalBlock from '../molecules/CollapsibleGoalBlock';
import styles from './GoalTabs.module.css';
import { EasyCryptGoal } from '../../types';

interface GoalTabsProps {
  goals: EasyCryptGoal[];
  onToggleGoalOpen?: (goalId: number, isOpen: boolean) => void;
  onToggleGoalContextHidden?: (goalId: number, isContextHidden: boolean) => void;
}

const GoalTabs: React.FC<GoalTabsProps> = ({ goals, onToggleGoalOpen, onToggleGoalContextHidden }) => {
  const [active, setActive] = useState(0);
  const tabRefs = useRef<HTMLButtonElement[]>([]);
  const endRefs = useRef<HTMLDivElement[]>([]);

  useEffect(() => {
    if (active >= goals.length) setActive(Math.max(0, goals.length - 1));
  }, [goals.length, active]);

  // Auto-scroll to bottom of active goal after render
  useEffect(() => {
    const el = endRefs.current[active];
    if (el && el.scrollIntoView) {
      setTimeout(() => el.scrollIntoView({ behavior: 'smooth', block: 'end', inline: 'nearest' }), 150);
    }
  }, [active, goals]);

  const onKeyDown = (e: React.KeyboardEvent<HTMLButtonElement>, index: number) => {
    let next = index;
    if (e.key === 'ArrowRight') next = (index + 1) % goals.length;
    else if (e.key === 'ArrowLeft') next = (index - 1 + goals.length) % goals.length;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = goals.length - 1;
    else return;
    e.preventDefault();
    setActive(next);
    tabRefs.current[next]?.focus();
  };

  return (
    <div className={styles.tabsRoot}>
      <div className={styles.tabsHeader} role="tablist" aria-label="Goals">
        {goals.map((g, i) => (
          <button
            key={g.id ?? i}
            ref={el => { if (el) tabRefs.current[i] = el; }}
            role="tab"
            aria-selected={active === i}
            aria-controls={`goal-tabpanel-${i}`}
            id={`goal-tab-${i}`}
            className={`${styles.tabButton} ${active === i ? styles.tabButtonActive : ''}`}
            onClick={() => setActive(i)}
            onKeyDown={(e) => onKeyDown(e, i)}
          >
            Goal {i + 1}
          </button>
        ))}
      </div>
      {goals.map((g, i) => (
        <div
          key={`panel-${g.id ?? i}`}
          role="tabpanel"
          id={`goal-tabpanel-${i}`}
          aria-labelledby={`goal-tab-${i}`}
          className={`${styles.tabPanel} ${active === i ? styles.tabPanelActive : ''}`}
        >
          <CollapsibleGoalBlock 
            id={g.id} 
            index={i} 
            count={goals.length} 
            hypotheses={g.hypotheses}
            hypotheses_pp={g.hypotheses_pp}
            goal={g.goal}
            goal_pp={g.goal_pp}
            isOpen={g.isOpen}
            isContextHidden={g.isContextHidden}
            onToggleOpen={onToggleGoalOpen}
            onToggleContextHidden={onToggleGoalContextHidden}
          />
          <div ref={el => { if (el) endRefs.current[i] = el; }} />
        </div>
      ))}
    </div>
  );
};

export default GoalTabs;


