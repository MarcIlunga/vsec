import React, { useRef, useEffect, useState } from 'react';
import * as monaco from 'monaco-editor';
import styles from './SyntaxHighlightedGoal.module.css';

interface LspSyntaxHighlightedGoalProps {
  content: string;
  language?: string;
  readOnly?: boolean;
  className?: string;
  onLspRequest?: (method: string, params: any) => Promise<any>;
}

const LspSyntaxHighlightedGoal: React.FC<LspSyntaxHighlightedGoalProps> = ({
  content,
  language = 'easycrypt',
  readOnly = true,
  className = '',
  onLspRequest
}) => {
  const editorRef = useRef<HTMLDivElement>(null);
  const editorInstanceRef = useRef<monaco.editor.IStandaloneCodeEditor | null>(null);
  const [isLspConnected, setIsLspConnected] = useState(false);

  useEffect(() => {
    if (!editorRef.current) return;

    // Create Monaco editor instance
    const editor = monaco.editor.create(editorRef.current, {
      value: content,
      language: language,
      readOnly: readOnly,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      wordWrap: 'on',
      lineNumbers: 'off',
      glyphMargin: false,
      folding: false,
      lineDecorationsWidth: 0,
      lineNumbersMinChars: 0,
      renderLineHighlight: 'none',
      scrollbar: {
        vertical: 'auto',
        horizontal: 'auto',
        useShadows: false,
        verticalScrollbarSize: 8,
        horizontalScrollbarSize: 8,
      },
      theme: 'vs-dark',
      fontSize: 13,
      fontFamily: 'var(--vscode-editor-font-family, "Consolas", "Courier New", monospace)',
      automaticLayout: true,
    });

    editorInstanceRef.current = editor;

    // Apply VS Code theme colors
    const applyTheme = () => {
      const root = document.documentElement;
      const computedStyle = getComputedStyle(root);
      
      const theme = {
        base: 'vs-dark' as const,
        inherit: true,
        rules: [
          {
            token: 'comment',
            foreground: computedStyle.getPropertyValue('--vscode-textPreformat-foreground').trim() || '#6A9955',
          },
          {
            token: 'keyword',
            foreground: computedStyle.getPropertyValue('--vscode-textLink-foreground').trim() || '#569CD6',
          },
          {
            token: 'string',
            foreground: computedStyle.getPropertyValue('--vscode-textPreformat-foreground').trim() || '#CE9178',
          },
          {
            token: 'number',
            foreground: computedStyle.getPropertyValue('--vscode-textPreformat-foreground').trim() || '#B5CEA8',
          },
          {
            token: 'type',
            foreground: computedStyle.getPropertyValue('--vscode-textLink-foreground').trim() || '#4EC9B0',
          },
          {
            token: 'function',
            foreground: computedStyle.getPropertyValue('--vscode-textLink-foreground').trim() || '#DCDCAA',
          },
          {
            token: 'variable',
            foreground: computedStyle.getPropertyValue('--vscode-editor-foreground').trim() || '#9CDCFE',
          },
          {
            token: 'property',
            foreground: computedStyle.getPropertyValue('--vscode-textPreformat-foreground').trim() || '#9CDCFE',
          },
        ],
        colors: {
          'editor.background': computedStyle.getPropertyValue('--vscode-editor-background').trim() || '#1e1e1e',
          'editor.foreground': computedStyle.getPropertyValue('--vscode-editor-foreground').trim() || '#d4d4d4',
          'editor.selectionBackground': computedStyle.getPropertyValue('--vscode-editor-selectionBackground').trim() || '#264f78',
        }
      };

      monaco.editor.defineTheme('vscode-theme', theme);
      monaco.editor.setTheme('vscode-theme');
    };

    // Apply theme immediately and on theme changes
    applyTheme();
    
    // Listen for theme changes
    const observer = new MutationObserver(applyTheme);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme', 'class']
    });

    // Request semantic tokens from LSP server
    const requestSemanticTokens = async () => {
      if (!onLspRequest) return;

      try {
        // Request semantic tokens for the full document
        const result = await onLspRequest('textDocument/semanticTokens/full', {
          textDocument: {
            uri: 'file:///goal-content.ec', // Virtual URI for goal content
            version: 1
          }
        });

        if (result && result.data) {
          // Decode semantic tokens data
          const tokens = decodeSemanticTokensData(result.data);
          applySemanticTokens(editor, tokens);
          setIsLspConnected(true);
        }
      } catch (error) {
        console.warn('Failed to get semantic tokens from LSP:', error);
        setIsLspConnected(false);
      }
    };

    // Request semantic tokens after a short delay to ensure LSP is ready
    const timeoutId = setTimeout(requestSemanticTokens, 1000);

    return () => {
      clearTimeout(timeoutId);
      observer.disconnect();
      editor.dispose();
    };
  }, [onLspRequest]);

  // Update content when it changes
  useEffect(() => {
    if (editorInstanceRef.current && editorInstanceRef.current.getValue() !== content) {
      editorInstanceRef.current.setValue(content);
      
      // Re-request semantic tokens for new content
      if (onLspRequest) {
        setTimeout(() => {
          onLspRequest('textDocument/semanticTokens/full', {
            textDocument: {
              uri: 'file:///goal-content.ec',
              version: 1
            }
          }).then(result => {
            if (result && result.data) {
              const tokens = decodeSemanticTokensData(result.data);
              applySemanticTokens(editorInstanceRef.current!, tokens);
            }
          }).catch(console.warn);
        }, 100);
      }
    }
  }, [content, onLspRequest]);

  return (
    <div className={`${styles.container} ${className}`}>
      <div ref={editorRef} className={styles.editor} />
      {!isLspConnected && (
        <div className={styles.lspStatus}>
          <small>LSP syntax highlighting unavailable</small>
        </div>
      )}
    </div>
  );
};

// Decode LSP semantic tokens data (delta-encoded)
function decodeSemanticTokensData(data: number[]): Array<{
  line: number;
  startChar: number;
  length: number;
  tokenType: number;
  tokenModifiers: number;
}> {
  const tokens: Array<{
    line: number;
    startChar: number;
    length: number;
    tokenType: number;
    tokenModifiers: number;
  }> = [];

  let prevLine = 0;
  let prevStartChar = 0;

  for (let i = 0; i < data.length; i += 5) {
    const deltaLine = data[i];
    const deltaStartChar = data[i + 1];
    const length = data[i + 2];
    const tokenType = data[i + 3];
    const tokenModifiers = data[i + 4];

    const line = prevLine + deltaLine;
    const startChar = deltaLine === 0 ? prevStartChar + deltaStartChar : deltaStartChar;

    tokens.push({
      line,
      startChar,
      length,
      tokenType,
      tokenModifiers
    });

    prevLine = line;
    prevStartChar = startChar;
  }

  return tokens;
}

// Apply semantic tokens to Monaco Editor
function applySemanticTokens(editor: monaco.editor.IStandaloneCodeEditor, tokens: Array<{
  line: number;
  startChar: number;
  length: number;
  tokenType: number;
  tokenModifiers: number;
}>) {
  const model = editor.getModel();
  if (!model) return;

  // Map LSP token types to Monaco token types
  const tokenTypeMap = [
    'keyword',    // 0
    'type',       // 1
    'function',   // 2
    'variable',   // 3
    'property',   // 4
    'comment',    // 5
  ];

  // Create decorations for semantic tokens
  const decorations = tokens.map(token => {
    const tokenType = tokenTypeMap[token.tokenType] || 'variable';
    const range = new monaco.Range(
      token.line + 1, // Monaco uses 1-based line numbers
      token.startChar + 1, // Monaco uses 1-based column numbers
      token.line + 1,
      token.startChar + token.length + 1
    );

    return {
      range,
      options: {
        inlineClassName: `semantic-token-${tokenType}`,
        hoverMessage: { value: `Token: ${tokenType}` }
      }
    };
  });

  // Apply decorations
  editor.deltaDecorations([], decorations);
}

export default LspSyntaxHighlightedGoal;
