// Inline type definitions to avoid importing from outside rootDir
// These are copies of types from goal-view-ui/src/types.ts

export interface Message {
  text: string;
  severity: 1 | 2 | 3 | 4;
  range: {
    start: { line: number; character: number };
    end: { line: number; character: number };
  };
}

export interface ExecutionOverview {
  processed: Array<{
    start: { line: number; character: number };
    end: { line: number; character: number };
  }>;
  processing: Array<{
    start: { line: number; character: number };
    end: { line: number; character: number };
  }>;
  prepared: Array<{
    start: { line: number; character: number };
    end: { line: number; character: number };
  }>;
}

export interface ProofViewMessage {
  type: 'proofView';
  textDocument: {
    uri: string;
    version: number;
  };
  proofState: any | null; // Use any to avoid importing EasyCryptProofState
}

export interface ExecutionOverviewMessage {
  type: 'executionOverview';
  textDocument: { uri: string; version: number };
  overview: ExecutionOverview;
}

export interface MessagesMessage {
  type: 'messages';
  textDocument: { uri: string; version: number };
  messages: Message[];
}
