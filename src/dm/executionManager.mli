(**************************************************************************)
(*                                                                        *)
(*                                 VSCoq                                  *)
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

open Types
open EcLib
open Lsp.LspData



(** Execution state, includes the cache *)
type state
type event
type events = event Sel.event list
(* val pr_event : event -> Pp.t *)

(* val init : Vernacstate.t -> state * event Sel.event *)

val invalidate : Scheduler.schedule -> sentence_id -> state -> state
val errors : state -> (sentence_id * (EcLocation.t option * string)) list
val feedback : state -> (sentence_id * (Severity.t * EcLocation.t option * string)) list
val shift_locs : state -> int -> int -> state
val executed_ids : state -> sentence_id list
val is_executed : state -> sentence_id -> bool
val is_remotely_executed : state -> sentence_id -> bool
(* val get_proof : state -> sentence_id -> Proof.t option
val get_proofview : state -> sentence_id -> Proof.data option
val get_context : state -> sentence_id -> (Evd.evar_map * Environ.env) option
val get_lemmas : Evd.evar_map -> Environ.env -> completion_item list *)

(** Events for the main loop *)
val handle_event : event -> state -> (state option * events)

(** Execution happens in two steps. In particular the event one takes only
    one task at a time to ease checking for interruption *)
type prepared_task
val build_tasks_for : Scheduler.schedule -> state -> sentence_id -> Vernacstate.t * prepared_task list
val execute : state -> Vernacstate.t * events * bool -> prepared_task -> (state * Vernacstate.t * events * bool)
