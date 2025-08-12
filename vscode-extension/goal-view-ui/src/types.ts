// EasyCrypt Goal View Types - Adapted from VSCoq
export interface EasyCryptGoal {
  id: number;
  hypotheses: string[];
  goal: string;
}

export interface ProofStepInfo {
  step_id: number;
  command: string;
  position: {
    line: number;
    character: number;
  };
  timestamp: number;
  goals_before: EasyCryptGoal[];
  goals_after: EasyCryptGoal[];
}

export interface ProofNavigation {
  current_step: number;
  total_steps: number;
  can_step_forward: boolean;
  can_step_backward: boolean;
  step_history: ProofStepInfo[];
}

export interface EasyCryptProofState {
  goals: EasyCryptGoal[];
  shelvedGoals: EasyCryptGoal[];
  givenUpGoals: EasyCryptGoal[];
  unfocusedGoals: EasyCryptGoal[];
  navigation?: ProofNavigation;
  current_lemma?: string;
  proof_progress?: number; // 0.0 to 1.0
}

export interface ProofViewMessage {
  type: 'proofView';
  textDocument: {
    uri: string;
    version: number;
  };
  proofState: EasyCryptProofState | null;
}

export interface VSCodeApi {
  postMessage(message: any): void;
  setState(state: any): void;
  getState(): any;
}

declare global {
  interface Window {
    acquireVsCodeApi(): VSCodeApi;
  }
}