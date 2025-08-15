import React from 'react';
import { VSCodeCheckbox } from '@vscode/webview-ui-toolkit/react';

type Props = {
  showError: boolean;
  showWarning: boolean;
  showInfo: boolean;
  showHint: boolean;
  onChange: (key: 'error'|'warning'|'info'|'hint', value: boolean) => void;
};

const MessageFilterBar: React.FC<Props> = ({ showError, showWarning, showInfo, showHint, onChange }) => {
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <span>Filter:</span>
      <VSCodeCheckbox checked={showError} onChange={(e: any) => onChange('error', e.target.checked)}>Errors</VSCodeCheckbox>
      <VSCodeCheckbox checked={showWarning} onChange={(e: any) => onChange('warning', e.target.checked)}>Warnings</VSCodeCheckbox>
      <VSCodeCheckbox checked={showInfo} onChange={(e: any) => onChange('info', e.target.checked)}>Info</VSCodeCheckbox>
      <VSCodeCheckbox checked={showHint} onChange={(e: any) => onChange('hint', e.target.checked)}>Hints</VSCodeCheckbox>
    </div>
  );
};

export default MessageFilterBar;


