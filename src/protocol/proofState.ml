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

open Printing
open Lsp.Types
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type proof_statement = {
  statement: string;
  range: Range.t;
} [@@deriving yojson]

type proof_step = {
  tactic: string;
  range: Range.t;
} [@@deriving yojson]

type proof_block = {
  statement: proof_statement;
  range: Range.t;
  steps: proof_step list;
} [@@deriving yojson]

(* EasyCrypt simplified goal type - plain strings for web UI compatibility *)
(* Minimal EasyCrypt PpString support (compatible with VSCoq-style segments) *)
type pp_atom = {
  text: string;
  cls: string option; (* e.g., "keyword", "ident", "type", etc. *)
} [@@deriving yojson]

type pp = pp_atom list [@@deriving yojson]

type goal = {
  id: int;
  (* Plain strings for current UI rendering *)
  hypotheses: string list;
  goal: string;
  (* Enhanced pretty-printed representations for future rendering *)
  hypotheses_pp: pp list; (* one pp per hypothesis *)
  goal_pp: pp;
} [@@deriving yojson]

type proof_step_info = {
  step_id: int;
  command: string;
  position: Lsp.Types.Position.t;
  timestamp: float;
  goals_before: goal list;
  goals_after: goal list;
} [@@deriving yojson]

type proof_navigation = {
  current_step: int;
  total_steps: int;
  can_step_forward: bool;
  can_step_backward: bool;
  step_history: proof_step_info list;
} [@@deriving yojson]

type t = {
  goals: goal list;
  shelvedGoals: goal list;
  givenUpGoals: goal list;
  unfocusedGoals: goal list;
  navigation: proof_navigation option;
  current_lemma: string option;
  proof_progress: float; (* 0.0 to 1.0 completion *)
} [@@deriving yojson]

(** Create goal from EasyCrypt proof context *)
let mk_goal id hypotheses goal_text =
  let mk_pp s : pp = [{ text = s; cls = None }] in
  {
    id;
    hypotheses = hypotheses;
    goal = goal_text;
    hypotheses_pp = List.map mk_pp hypotheses;
    goal_pp = mk_pp goal_text;
  }

(* Real EasyCrypt goal extraction helpers *)
let extract_real_easycrypt_goals env =
  (* TODO: Integrate with EasyCrypt APIs to retrieve actual proof obligations *)
  []

let extract_context_as_goals env =
  (* Optional: derive a lightweight context preview; keep disabled to avoid dummy content *)
  []

(** Extract goals from EasyCrypt proof context *)
let extract_easycrypt_goals scope =
  let _env = EcLib.EcScope.env scope in
  (* Until real extraction is implemented, do not fabricate goals *)
  []

(** Create enhanced navigation info *)
let mk_navigation ~current_step ~total_steps ~can_step_forward ~can_step_backward history =
  {
    current_step;
    total_steps;
    can_step_forward;
    can_step_backward;
    step_history = history;
  }

(** Extract proof state from EasyCrypt scope - ENHANCED implementation *)
let get_proof ~previous scope =
  let goals = extract_easycrypt_goals scope in
  match goals with
  | [] -> None
  | active_goals ->
    Some {
      goals = active_goals;
      shelvedGoals = [];
      givenUpGoals = [];
      unfocusedGoals = [];
      navigation = None;
      current_lemma = None;
      proof_progress = 0.0;
    }

let of_strings (gs: string list) : t =
  let mk idx s = mk_goal idx [] s in
  {
    goals = List.mapi mk gs;
    shelvedGoals = [];
    givenUpGoals = [];
    unfocusedGoals = [];
    navigation = None;
    current_lemma = None;
    proof_progress = 0.0;
  }

let mk_proof_statement statement range = {statement; range}

let mk_proof_step tactic range = {tactic; range}

let mk_proof_block statement steps range = {steps; statement; range}