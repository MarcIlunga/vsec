import React from 'react';
import LspSyntaxHighlightedGoal from './LspSyntaxHighlightedGoal';
import LspService from '../../services/LspService';

// Pretty-printer adapter with LSP-based syntax highlighting
// Uses Monaco Editor with semantic tokens from the LSP server

interface PpRendererProps {
  content: string;
}

const PpRenderer: React.FC<PpRendererProps> = ({ content }) => {
  const lspService = LspService.getInstance();

  return (
    <LspSyntaxHighlightedGoal 
      content={content} 
      onLspRequest={lspService.request.bind(lspService)}
    />
  );
};

export default PpRenderer;


