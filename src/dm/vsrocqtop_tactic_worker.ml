(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                  *)
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

(** This toplevel implements an LSP-based server language for VsCode,
    used by the VsRocq extension. *)

let log = Dm.ParTactic.TacticWorkerProcess.log 

let main_worker options ~opts:_ state =
  let initial_vernac_state = Vernacstate.freeze_full_state () in
  try Dm.ParTactic.TacticWorkerProcess.main ~st:initial_vernac_state options
  with exn ->
    let bt = Printexc.get_backtrace () in
    log (fun () -> Printexc.(to_string exn));
    log (fun () -> bt);
    flush_all ()

let vsrocqtop_specific_usage = Boot.Usage.{
  executable_name = "vsrocqtop_tactic_worker";
  extra_args = "";
  extra_options = "";
}



