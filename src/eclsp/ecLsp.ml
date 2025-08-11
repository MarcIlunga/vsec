(**************************************************************************)
(*                                                                        *)
(*                                 VsEc                                   *)
(*                                                                        *)
(*                   Copyright EasyCrypt contributors                      *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

(** This toplevel implements an LSP-based server language for VsCode,
    used by the VsEc extension. Rewritten from VSRocq reference. *)

let Dm.Types.Log log = Dm.Log.mk_log "top"

let loop () =
  let events = LspManager.init () in
  let rec loop (todo : LspManager.event Sel.Todo.t) =
    (*log (fun () -> "looking for next step");*)
    flush_all ();
    let ready, todo = Sel.pop todo in
    let nremaining = Sel.Todo.size todo in
    log (fun () -> Printf.sprintf "Main loop event ready: %s, %d events waiting\n\n" (LspManager.pr_event ready) nremaining);
    log (fun () -> "==========================================================");
    log (fun () -> Printf.sprintf "Todo events: %s" "events"); (* simplified for EasyCrypt *)
    log (fun () -> "==========================================================\n\n");
    let new_events = LspManager.handle_event ready in
    let todo = Sel.Todo.add todo new_events in
    log (fun () -> "==========================================================");
    log (fun () -> Printf.sprintf "New Todo events: %s" "new events"); (* simplified for EasyCrypt *)
    log (fun () -> "==========================================================\n\n");
    loop todo
  in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  try loop todo
  with exn ->
    let info = (exn, Printexc.get_raw_backtrace ()) in
    log ~force:true (fun () -> "==========================================================");
    log ~force:true (fun () -> Printf.sprintf "Exception: %s" (Printexc.to_string (fst info)));
    log ~force:true (fun () -> "==========================================================")

let () =
  Printexc.record_backtrace true;
  log (fun () -> "------------------ VsEc EasyCrypt LSP Server begin ---------------");
  let cwd = Unix.getcwd () in
  log (fun () -> Printf.sprintf "Working directory: %s" cwd);
  Sys.(set_signal sigint Signal_ignore);
  loop ()
