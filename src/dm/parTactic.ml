(**************************************************************************)
(*                                                                        *)
(*                                 VSec - EasyCrypt Language Server       *)
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

(* TODO: Implement EasyCrypt parallel tactics system *)
(* Temporarily disabled Coq parallel tactics for build success *)

open Types

let Log log = Log.mk_log "parTactic"

type sentence_id = int

(* Placeholder module - will be replaced with EasyCrypt implementation *)
module TacticJob = struct
  type solution =
    | Solved of string * unit
    | NoProgress  
    | Error of string
    
  type update_request =
    | UpdateSolution of string * solution  (* simplified without Evar.t *)
    | AppendFeedback of int * sentence_id * (DiagnosticSeverity.t * EasyCryptLocation.t option * string)
    
  let appendFeedback (rid,id) fb = AppendFeedback(rid,id,fb)

  type t = {
    state : EcLib.EcScope.scope;
    ast : string; (* simplified AST *)
    goalno : int;
    goal : string; (* simplified goal *)
    name : string;
  }
  
  let name = "tactic"
  let binary_name = "vsec_tactic_worker"
  let initial_pool_size = 0 (* disabled for now *)
end

(* Temporarily comment out worker system for build success *)
(* module TacticWorker = DelegationManager.MakeWorker(TacticJob) *)

(* Placeholder functions for parallel tactics - disabled for build success *)
let set_id_for_feedback _rid _sid = ()

(* Stub function to replace complex Coq parallel tactics *)
let interp_par ~pstate ~info:_ ~ast:_ ~abstract:_ = pstate

(* 
   Complete parallel tactic system disabled for build success.
   TODO: Implement EasyCrypt parallel tactics when needed.
*)

(* Placeholder module to satisfy interface *)
module TacticWorkerProcess = struct
  type options = unit
  let parse_options _args = (), []
  let main ~st:_ _options = ()
  let log ?force:_ _f = ()
end
