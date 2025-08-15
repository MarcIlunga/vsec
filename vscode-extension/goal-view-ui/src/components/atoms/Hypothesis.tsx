import React, {FunctionComponent} from 'react';

import classes from './PpString.module.css';
import { PpString } from '../../types';

type HypothesisProps = {
    content: PpString;
    maxDepth: number;
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

const hypothesis: FunctionComponent<HypothesisProps> = (props) => {
    
    const {content, maxDepth} = props;

    return (
        <div className={classes.Hypothesis}>
            {renderPpString(content)}
        </div>
    );
};

export default hypothesis;