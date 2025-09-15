import React from 'react';
import styles from './Message.module.css';
import '@vscode-elements/elements/dist/vscode-icon';

interface MessageProps {
  severity: 'info' | 'warning' | 'error';
  text: string;
}

const Message: React.FC<MessageProps> = ({ severity, text }) => {
  const icon = severity === 'error' ? 'error' : severity === 'warning' ? 'warning' : 'info';
  const sevClass = severity === 'error' ? styles.error : severity === 'warning' ? styles.warn : styles.info;
  return (
    <div className={styles.item}>
      <vscode-icon className={sevClass} name={icon}></vscode-icon>
      <span>{text}</span>
    </div>
  );
};

export default Message;


