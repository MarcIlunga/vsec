(**************************************************************************)
(*                                                                        *)
(*                                 VsEc                                   *)
(*                                                                        *)
(*   Optional EasyCrypt execution adapter via Dynlink                     *)
(*                                                                        *)
(**************************************************************************)

open Types

let Log log = Log.mk_log "ecAdapter"

(* Execution adapter *)

type ec_process = EcLib.EcScope.scope -> string -> EcLib.EcScope.scope

let process_ref : ec_process option ref = ref None

let register (f:ec_process) =
  log (fun () -> "Registered EasyCrypt execution adapter");
  process_ref := Some f

let try_process scope cmd =
  match !process_ref with
  | None -> None
  | Some f ->
    try Some (f scope cmd) with exn ->
      log (fun () -> ("Adapter process failed: " ^ Printexc.to_string exn));
      None

(* Goals adapter *)

type ec_goals = EcLib.EcScope.scope -> Protocol.ProofState.goal list

let goals_ref : ec_goals option ref = ref None

let register_goals (f:ec_goals) =
  log (fun () -> "Registered EasyCrypt goals adapter");
  goals_ref := Some f

let try_goals scope =
  match !goals_ref with
  | None -> None
  | Some f ->
    try Some (f scope) with exn ->
      log (fun () -> ("Adapter goals failed: " ^ Printexc.to_string exn));
      None

let adapter_loaded = ref false

let try_dynlink () =
  if not !adapter_loaded then begin
    adapter_loaded := true;
    let path = Sys.getenv_opt "VSEC_EC_ADAPTER" |> Option.value ~default:"vsec_ec_adapter.cmxs" in
    try
      log (fun () -> ("Trying to dynlink EC adapter: " ^ path));
      Dynlink.loadfile path;
      log (fun () -> "Dynlink of EC adapter succeeded")
    with exn ->
      log (fun () -> ("Dynlink of EC adapter failed: " ^ Printexc.to_string exn));
      ()
  end


