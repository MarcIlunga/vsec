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

(* MINIMAL LSP - simplified logging *)
let log msg = Printf.eprintf "[TOP] %s\n" msg; flush stderr

let loop () =
  log "Starting LSP event loop";
  let events = LspManager.init () in
  let rec loop (todo : LspManager.event Sel.Todo.t) =
    flush_all ();
    let ready, todo = Sel.pop todo in
    let nremaining = Sel.Todo.size todo in
    log (Printf.sprintf "Main loop event ready: %s, %d events waiting" (LspManager.pr_event ready) nremaining);
    let new_events = LspManager.handle_event ready in
    let todo = Sel.Todo.add todo new_events in
    log (Printf.sprintf "Added %d new events" (List.length new_events));
    loop todo
  in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  try loop todo
  with exn ->
    let info = (exn, Printexc.get_raw_backtrace ()) in
    log (Printf.sprintf "EXCEPTION: %s" (Printexc.to_string (fst info)))

let () =
  Printexc.record_backtrace true;
  log "VsEc EasyCrypt LSP Server starting (minimal mode)";
  let cwd = Unix.getcwd () in
  log (Printf.sprintf "Working directory: %s" cwd);
  Sys.(set_signal sigint Signal_ignore);
  loop ()
