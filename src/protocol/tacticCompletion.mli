(**************************************************************************)
(*                                                                        *)
(*                                 VsEc                                   *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

open Lsp.Types

(** Duplicate types to avoid module resolution issues *)
type tactic_goal = {
  goal_id: int;
  goal_hypotheses: Printing.pp list;
  goal_conclusion: Printing.pp;
}

(** Type of tactic categories for organizing suggestions *)
type tactic_category = 
  | LogicalReasoning
  | Rewriting
  | Automation
  | Structural
  | Arithmetic
  | Advanced

(** Tactic suggestion with context awareness *)
type tactic_suggestion = {
  name: string;
  category: tactic_category;
  description: string;
  syntax: string;
  example: string;
  relevance_score: float;
  applicable_contexts: string list;
}

(** Generate contextual tactic completions based on current goal and hypotheses *)
val get_tactic_completions : tactic_goal -> Printing.pp list -> string -> CompletionItem.t list

(** Enhanced completion with tactic arguments and context-specific suggestions *)
val get_enhanced_completions : tactic_goal -> Printing.pp list -> string -> Position.t -> CompletionItem.t list

(** Analyze goal context to determine applicable tactics *)
val analyze_goal_context : tactic_goal -> string list