(**************************************************************************)
(*                                                                        *)
(*                                 VSec                                   *)
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
open Protocol
open Protocol.LspWrapper

(** The execution manager handles EasyCrypt sentence execution and state management *)

type delegation_mode =
  | CheckProofsInMaster
  | SkipProofs

type options = {
  delegation_mode : delegation_mode;
  enableDiagnostics : bool;
}

val is_diagnostics_enabled: unit -> bool

(** Execution state, includes the cache *)
type state
type event
type events = event Sel.Event.t list
type errored_sentence = (sentence_id * EasyCryptLocation.t option) option

(* EasyCrypt feedback message - simplified from Coq's feedback system *)
type feedback_message = DiagnosticSeverity.t * EasyCryptLocation.t option * string

val pr_event : event -> string
val init : EcLib.EcScope.scope -> state * event Sel.Event.t
val destroy : state -> unit

val get_options : unit -> options
val set_options : options -> unit
val set_default_options : unit -> unit
val invalidate : Document.document -> Scheduler.schedule -> sentence_id -> state -> state

val error : state -> sentence_id -> (EasyCryptLocation.t option * string) option
val feedback :  state -> sentence_id -> feedback_message list
val all_errors : state -> (sentence_id * (EasyCryptLocation.t option * string)) list
val all_feedback : state -> (sentence_id * feedback_message) list

val reset_overview : state -> Document.document -> state
val shift_overview : state -> before:RawDocument.t -> after:RawDocument.t -> start:int -> offset:int -> state
val shift_diagnostics_locs : state -> start:int -> offset:int -> state
val executed_ids : state -> sentence_id list

(** we know if it worked and we have the state in this process *)
val is_locally_executed : state -> sentence_id -> bool

(** we know if it worked but we do not have the state in this process *)
val is_remotely_executed : state -> sentence_id -> bool

val get_context : state -> sentence_id -> EcLib.EcScope.scope option
val get_initial_context : state -> EcLib.EcScope.scope

(** Returns the EasyCrypt scope state after the sentence *)
val get_easycrypt_state : state -> sentence_id -> EcLib.EcScope.scope option

(** Events for the main loop *)
val handle_event : event -> state -> (sentence_id option * state option * events)

(** Execution happens in two steps. In particular the event one takes only
    one task at a time to ease checking for interruption *)
type prepared_task
val get_id_of_executed_task : prepared_task -> sentence_id
val build_tasks_for : Document.document -> Scheduler.schedule -> state -> sentence_id -> bool -> EcLib.EcScope.scope * state * prepared_task option * errored_sentence
val execute : state -> Document.document -> EcLib.EcScope.scope * events * bool -> prepared_task -> bool -> (prepared_task option * state * EcLib.EcScope.scope * events * errored_sentence)

val update_processed : sentence_id -> state -> Document.document -> state
val prepare_overview : state -> LspWrapper.Range.t list -> state
val overview : state -> exec_overview
val overview_until_range : state -> LspWrapper.Range.t -> exec_overview
val print_exec_overview_of_state : state -> unit