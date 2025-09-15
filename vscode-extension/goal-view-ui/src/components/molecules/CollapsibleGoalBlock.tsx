import { FunctionComponent } from 'react';
import GoalBlock from './GoalBlock';
import Accordion from '../atoms/Accordion';

interface CollapsibleGoalBlockProps {
  id?: number;
  index?: number;
  count?: number;
  hypotheses: string[];
  goal: string;
  isOpen?: boolean;
  isContextHidden?: boolean;
  onToggleOpen?: (goalId: number, isOpen: boolean) => void;
  onToggleContextHidden?: (goalId: number, isContextHidden: boolean) => void;
}

const CollapsibleGoalBlock: FunctionComponent<CollapsibleGoalBlockProps> = (props) => {
  const { 
    id, 
    index, 
    count, 
    hypotheses, 
    goal, 
    isOpen = true, 
    isContextHidden = false, 
    onToggleOpen, 
    onToggleContextHidden 
  } = props;

  const goalIndex = typeof index === 'number' ? index + 1 : 1;
  const goalTitle = `Goal ${goalIndex}`;
  
  const secondaryActionIcon = isContextHidden ? 'eye' : 'eye-closed';
  const secondaryActionHandler = hypotheses.length > 0 && id !== undefined && onToggleContextHidden 
    ? () => onToggleContextHidden(id, !isContextHidden) 
    : undefined;

  const collapseHandler = id !== undefined && onToggleOpen 
    ? () => onToggleOpen(id, !isOpen) 
    : undefined;

  return (
    <Accordion 
      title={goalTitle} 
      collapsed={!isOpen}
      collapseHandler={collapseHandler}
      secondaryActionHandler={secondaryActionHandler}
      secondaryActionIcon={secondaryActionIcon}
    >
      <GoalBlock 
        id={id}
        index={index}
        count={count}
        hypotheses={hypotheses}
        goal={goal}
        isContextHidden={isContextHidden}
      />
    </Accordion>
  );
};

export default CollapsibleGoalBlock;
