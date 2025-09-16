open Lsp.Types

type pp_atom = { text: string; cls: string option } [@@deriving yojson]

type pp = pp_atom list [@@deriving yojson]

type goal = {
  id: int;
  hypotheses: string list;
  goal: string;
  hypotheses_pp: pp list;
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
  proof_progress: float;
} [@@deriving yojson]

val get_proof : previous: t option -> EcLib.EcScope.scope -> t option

val of_strings : string list -> t