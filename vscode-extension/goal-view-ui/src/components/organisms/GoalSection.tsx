import React from 'react';
import CollapsibleGoalBlock from '../molecules/CollapsibleGoalBlock';
import GoalTabs from './GoalTabs';
import EmptyState from '../atoms/EmptyState';
import VirtualList from './VirtualList';
import { EasyCryptGoal } from '../../types';

interface GoalSectionProps {
  goals: EasyCryptGoal[];
  shelvedGoals?: EasyCryptGoal[];
  unfocusedGoals?: EasyCryptGoal[];
  givenUpGoals?: EasyCryptGoal[];
  display: 'Tabs' | 'List';
  // Goal state management - will be used when we restore full functionality
  goalStates?: Map<number, { isOpen: boolean; isContextHidden: boolean }>;
  onToggleGoalOpen?: (goalId: number, isOpen: boolean) => void;
  onToggleGoalContextHidden?: (goalId: number, isContextHidden: boolean) => void;
  prefs?: { defaultOpen: boolean; defaultContextHidden: boolean };
}

const GoalSection: React.FC<GoalSectionProps> = ({ 
  goals, 
  // shelvedGoals = [], // TODO: Will be used for complete section rendering 
  unfocusedGoals = [], 
  // givenUpGoals = [], // TODO: Will be used for complete section rendering
  display,
  goalStates,
  onToggleGoalOpen,
  onToggleGoalContextHidden,
  prefs = { defaultOpen: true, defaultContextHidden: false }
}) => {
  // Like vsrocq - show different sections based on which goals exist
  const hasMainGoals = goals && goals.length > 0;
  const hasUnfocusedGoals = unfocusedGoals.length > 0;
  // Note: hasShelvedGoals and hasGivenUpGoals will be used when we implement full section rendering

  // Enhanced goal helper - adds state information
  const enhanceGoalsWithState = (goalList: EasyCryptGoal[]) => {
    return goalList.map(goal => {
      const state = goalStates?.get(goal.id) || { 
        isOpen: prefs.defaultOpen, 
        isContextHidden: prefs.defaultContextHidden 
      };
      return {
        ...goal,
        isOpen: state.isOpen,
        isContextHidden: state.isContextHidden
      } as EasyCryptGoal;
    });
  };

  if (!hasMainGoals) {
    if (hasUnfocusedGoals) {
      // Like vsrocq - show unfocused goals with hint when main goals are empty
      return (
        <div>
          <EmptyState message="No current goals" />
          <div style={{ 
            fontStyle: 'italic', 
            fontSize: 'small', 
            opacity: 0.7,
            marginTop: '8px',
            marginBottom: '8px'
          }}>
            Next unfocused goals (focus with bullet):
          </div>
          {display === 'List' ? (
            <VirtualList
              items={enhanceGoalsWithState(unfocusedGoals)}
              estimatedItemHeight={120}
              renderItem={(g, i) => (
                <CollapsibleGoalBlock 
                  key={g.id ?? i} 
                  id={g.id} 
                  index={i} 
                  count={unfocusedGoals.length} 
                  hypotheses={g.hypotheses} 
                  hypotheses_pp={g.hypotheses_pp}
                  goal={g.goal}
                  goal_pp={g.goal_pp}
                  isOpen={g.isOpen}
                  isContextHidden={g.isContextHidden}
                  onToggleOpen={onToggleGoalOpen}
                  onToggleContextHidden={onToggleGoalContextHidden}
                />
              )}
            />
          ) : (
            <GoalTabs 
              goals={enhanceGoalsWithState(unfocusedGoals)}
              onToggleGoalOpen={onToggleGoalOpen}
              onToggleGoalContextHidden={onToggleGoalContextHidden}
            />
          )}
        </div>
      );
    }
    return <EmptyState message="No goals" />;
  }

  // Render main goals
  if (display === 'List') {
    return (
      <VirtualList
        items={enhanceGoalsWithState(goals)}
        estimatedItemHeight={120}
        renderItem={(g, i) => (
          <CollapsibleGoalBlock 
            key={g.id ?? i} 
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
        )}
      />
    );
  }
  
  // Tabs mode
  return (
    <GoalTabs 
      goals={enhanceGoalsWithState(goals)}
      onToggleGoalOpen={onToggleGoalOpen}
      onToggleGoalContextHidden={onToggleGoalContextHidden}
    />
  );
};

export default GoalSection;


