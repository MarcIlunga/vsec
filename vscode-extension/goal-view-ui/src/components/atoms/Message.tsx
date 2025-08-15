import React, {FunctionComponent} from 'react';

import classes from './PpString.module.css';
import { MessageSeverity, PpString } from '../../types';

type MessageProps = {
    message: PpString,
    severity: MessageSeverity,
    maxDepth: number
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

const message : FunctionComponent<MessageProps> = (props) => {
    
    const {message, severity, maxDepth} = props;

    const classNames = [classes.Message]; 

    switch(severity) {
        case MessageSeverity.error:
            classNames.push(classes.Error);
            break;

        case MessageSeverity.information: 
            classNames.push(classes.Info);
            break;

        case MessageSeverity.hint: 
            classNames.push(classes.Hint);
            break;

        case MessageSeverity.warning: 
            classNames.push(classes.Warning);
            break;
    }

    return (
        <span className={classNames.join(' ')}>
            {renderPpString(message)}
        </span>
    );
};

export default message;