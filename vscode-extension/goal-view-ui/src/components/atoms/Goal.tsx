import React, {FunctionComponent} from 'react';

import classes from './PpString.module.css';
import { PpString } from '../../types';

type GoalProps = {
    goal: PpString,
    maxDepth: number,
    setHelpMessage: (message: string) => void;
};

const renderPpString = (pp: PpString): React.ReactNode => {
    if (typeof pp === 'string') {
        return pp;
    }
    if (Array.isArray(pp) && pp.length === 2) {
        return <span className={pp[0]}>{pp[1]}</span>;
    }
    return pp;
};

const goal : FunctionComponent<GoalProps> = (props) => {
    
    const {goal, maxDepth, setHelpMessage} = props;

    return (
        <div 
            className={classes.Goal} 
            onMouseOver={() => {
                if(setHelpMessage !== undefined) {
                    setHelpMessage("EasyCrypt goal view - hover over terms for details.");
                }
            }}
            onMouseOut={() => {
                if(setHelpMessage !== undefined) {
                    setHelpMessage("");
                }
            }}
        >
            {renderPpString(goal)}
        </div>
    );
};

export default goal;