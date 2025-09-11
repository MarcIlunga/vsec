declare namespace JSX {
  interface IntrinsicElements {
    'vscode-tabs': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement>;
    'vscode-tab-header': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement> & { slot?: string }, HTMLElement>;
    'vscode-tab-panel': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement> & { id: string }, HTMLElement>;
    'vscode-badge': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement>;
    'vscode-button': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement> & { 
      appearance?: 'primary' | 'secondary' | 'icon';
      disabled?: boolean;
      onClick?: (event: MouseEvent) => void;
    }, HTMLElement>;
  }
}
