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

(** Helper function to take first n elements from list *)
let rec take n lst = match n, lst with
  | 0, _ -> []
  | _, [] -> []
  | n, x :: xs when n > 0 -> x :: take (n-1) xs
  | _, _ -> []

(** Duplicate types to avoid module resolution issues *)
type tactic_goal = {
  goal_id: int;
  goal_hypotheses: Printing.pp list;
  goal_conclusion: Printing.pp;
}

type tactic_category = 
  | LogicalReasoning     (* apply, intro, etc. *)
  | Rewriting           (* rewrite, unfold, etc. *)
  | Automation         (* auto, trivial, etc. *)
  | Structural         (* split, left, right, etc. *)
  | Arithmetic         (* field, ring, omega, etc. *)
  | Advanced           (* pose, assert, etc. *)

type tactic_suggestion = {
  name: string;
  category: tactic_category;
  description: string;
  syntax: string;
  example: string;
  relevance_score: float; (* 0.0 to 1.0 *)
  applicable_contexts: string list; (* goal patterns where this applies *)
}

(** Database of EasyCrypt tactics with smart contextual suggestions *)
let easycrypt_tactics = [
  {
    name = "intros";
    category = LogicalReasoning;
    description = "Introduce variables and hypotheses from the goal";
    syntax = "intros [var1] [var2] ...";
    example = "intros x H";
    relevance_score = 0.9;
    applicable_contexts = ["forall"; "->"; "=>"];
  };
  {
    name = "apply";
    category = LogicalReasoning;
    description = "Apply a lemma or hypothesis to the current goal";
    syntax = "apply lemma_name";
    example = "apply eq_refl";
    relevance_score = 0.8;
    applicable_contexts = ["="; "<="; "conclusion"];
  };
  {
    name = "rewrite";
    category = Rewriting;
    description = "Rewrite using an equality or equivalence";
    syntax = "rewrite [<-] lemma_name";
    example = "rewrite <- H1";
    relevance_score = 0.8;
    applicable_contexts = ["="; "<->"; "equiv"];
  };
  {
    name = "split";
    category = Structural;
    description = "Split a conjunction or equivalence";
    syntax = "split";
    example = "split";
    relevance_score = 0.7;
    applicable_contexts = ["/\\"; "<->"];
  };
  {
    name = "left";
    category = Structural;
    description = "Prove the left part of a disjunction";
    syntax = "left";
    example = "left";
    relevance_score = 0.6;
    applicable_contexts = ["\\/"];
  };
  {
    name = "right";
    category = Structural;
    description = "Prove the right part of a disjunction";
    syntax = "right";
    example = "right";
    relevance_score = 0.6;
    applicable_contexts = ["\\/"];
  };
  {
    name = "simplify";
    category = Automation;
    description = "Simplify expressions in the goal";
    syntax = "simplify";
    example = "simplify";
    relevance_score = 0.7;
    applicable_contexts = ["arithmetic"; "logic"];
  };
  {
    name = "trivial";
    category = Automation;
    description = "Try to solve goal with trivial methods";
    syntax = "trivial";
    example = "trivial";
    relevance_score = 0.6;
    applicable_contexts = ["="; "True"; "reflexive"];
  };
  {
    name = "auto";
    category = Automation;
    description = "Automatic proof search with built-in tactics";
    syntax = "auto";
    example = "auto";
    relevance_score = 0.8;
    applicable_contexts = ["simple"; "standard"];
  };
  {
    name = "unfold";
    category = Rewriting;
    description = "Unfold (expand) the definition of a symbol";
    syntax = "unfold definition_name";
    example = "unfold double";
    relevance_score = 0.7;
    applicable_contexts = ["definition"; "abbreviation"];
  };
  {
    name = "pose";
    category = Advanced;
    description = "Introduce a new local definition";
    syntax = "pose (name := expression)";
    example = "pose (x := a + b)";
    relevance_score = 0.5;
    applicable_contexts = ["complex_expression"];
  };
  {
    name = "assert";
    category = Advanced;
    description = "Assert an intermediate fact";
    syntax = "assert (hypothesis_name : statement)";
    example = "assert (H : x > 0)";
    relevance_score = 0.6;
    applicable_contexts = ["intermediate_step"];
  };
]

(** Analyze goal context to determine applicable tactics *)
let analyze_goal_context goal =
  let goal_text = Printing.string_of_pp goal.goal_conclusion in
  let contexts = ref [] in
  
  (* Pattern matching for goal structure *)
  if String.contains goal_text 'f' || Str.string_match (Str.regexp ".*forall.*") goal_text 0 then
    contexts := "forall" :: !contexts;
  if String.contains goal_text '>' || Str.string_match (Str.regexp ".*->.*") goal_text 0 then
    contexts := "->" :: !contexts;
  if Str.string_match (Str.regexp ".*/\\\\.*") goal_text 0 then
    contexts := "/\\" :: !contexts;
  if Str.string_match (Str.regexp ".*\\\\/.*") goal_text 0 then
    contexts := "\\/" :: !contexts;
  if String.contains goal_text '=' then
    contexts := "=" :: !contexts;
  if Str.string_match (Str.regexp ".*<->.*") goal_text 0 then
    contexts := "<->" :: !contexts;
  
  !contexts

(** Score tactic relevance based on current proof context *)
let score_tactic_relevance tactic goal hypotheses =
  let goal_contexts = analyze_goal_context goal in
  let base_score = tactic.relevance_score in
  
  (* Boost score if tactic is applicable to current context *)
  let context_bonus = 
    List.fold_left (fun acc context ->
      if List.mem context tactic.applicable_contexts then acc +. 0.3
      else acc
    ) 0.0 goal_contexts
  in
  
  (* Boost score based on available hypotheses *)
  let hypothesis_bonus =
    match tactic.name with
    | "apply" when List.length hypotheses > 0 -> 0.2
    | "rewrite" when List.exists (fun h -> String.contains (Printing.string_of_pp h) '=') hypotheses -> 0.3
    | _ -> 0.0
  in
  
  min 1.0 (base_score +. context_bonus +. hypothesis_bonus)

(** Generate contextual tactic completions *)
let get_tactic_completions goal hypotheses prefix =
  let applicable_tactics = 
    easycrypt_tactics
    |> List.filter (fun tactic -> 
        String.starts_with ~prefix:prefix tactic.name ||
        String.length prefix = 0)
    |> List.map (fun tactic ->
        let relevance = score_tactic_relevance tactic goal hypotheses in
        (tactic, relevance))
    |> List.sort (fun (_, r1) (_, r2) -> Float.compare r2 r1)
    |> take 10  (* Top 10 suggestions *)
  in
  
  applicable_tactics
  |> List.mapi (fun index (tactic, relevance) ->
      CompletionItem.create 
        ~label:tactic.name
        ~kind:CompletionItemKind.Function
        ~detail:(Printf.sprintf "%.0f%% • %s" (relevance *. 100.) tactic.syntax)
        ~documentation:(`String (Printf.sprintf 
            "**%s** - %s\n\n```easycrypt\n%s\n```\n\n*Example:*\n```easycrypt\n%s\n```"
            tactic.name 
            tactic.description 
            tactic.syntax 
            tactic.example))
        ~sortText:(Printf.sprintf "%02d_%s" index tactic.name)
        ~insertText:tactic.name
        ())

(** Enhanced completion with tactic arguments *)
let get_enhanced_completions goal hypotheses prefix position =
  let basic_completions = get_tactic_completions goal hypotheses prefix in
  
  (* Add context-specific argument suggestions *)
  let arg_completions = match prefix with
  | s when String.starts_with ~prefix:"apply " s ->
    (* Suggest available lemmas and hypotheses *)
    hypotheses 
    |> List.mapi (fun i h -> 
        let h_text = Printing.string_of_pp h in
        let first_part = match String.split_on_char ':' h_text with
        | name :: _ -> String.trim name
        | [] -> Printf.sprintf "H%d" i
        in
        CompletionItem.create
          ~label:first_part
          ~kind:CompletionItemKind.Variable
          ~detail:"Available hypothesis"
          ~insertText:first_part
          ())
  | s when String.starts_with ~prefix:"rewrite " s ->
    (* Suggest equality hypotheses *)
    hypotheses
    |> List.filter (fun h -> String.contains (Printing.string_of_pp h) '=')
    |> List.mapi (fun i h ->
        let h_text = Printing.string_of_pp h in
        let name = match String.split_on_char ':' h_text with
        | name :: _ -> String.trim name  
        | [] -> Printf.sprintf "H%d" i
        in
        CompletionItem.create
          ~label:name
          ~kind:CompletionItemKind.Variable
          ~detail:"Equality hypothesis"
          ~insertText:name
          ())
  | _ -> []
  in
  
  basic_completions @ arg_completions