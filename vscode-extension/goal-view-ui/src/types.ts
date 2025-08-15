// import { integer } from "vscode-languageclient";

type Nullable<T> = T | null;

// Simple PpString type for EasyCrypt (adapting VSCoq's format)
export type PpString = string | [string, string];

export interface Goal {
    id: string,
    goal: PpString, 
    hypotheses: PpString[],
};

export interface CollapsibleGoal extends Goal  {
    isOpen: boolean;
    isContextHidden: boolean;
};

export type ProofViewGoalsType = {
    main: CollapsibleGoal[];
    shelved: CollapsibleGoal[];
    givenUp: CollapsibleGoal[];
    unfocused: CollapsibleGoal[];
};

export enum ProofViewGoalsKey {
    main = "main", 
    shelved = "shelved", 
    givenUp = "givenUp",
    unfocused = "unfocused"
}

export enum MessageSeverity {
    error = 1, 
    warning,
    information,
    hint
}

export type ProofViewMessage = [MessageSeverity, PpString];

export type GoalArray = Goal[];

export type GoalArrayOrNull = Nullable<Goal[]>;

export type ProofViewGoals = Nullable<ProofViewGoalsType>;

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