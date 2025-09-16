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

(* --- Fallback lightweight goals provider (best-effort) --- *)

let fallback_goals_of_scope (scope:EcLib.EcScope.scope) : Protocol.ProofState.goal list =
  (* We do not have direct access to EasyCrypt proof engine; build a minimal goal from current context when possible. *)
  let mk text : Protocol.ProofState.goal =
    let open Protocol.ProofState in
    let atom s = { text = s; cls = None } in
    { id = 0; hypotheses = []; goal = text; hypotheses_pp = []; goal_pp = [atom text] }
  (* Try to find a pending goal string from scope by inspecting environment printing, if available. *)
  in []

let () =
  (* Register a fallback adapter if none is provided via dynlink, so callers can still receive a non-crashing result *)
  if !goals_ref = None then begin
    log (fun () -> "Registering fallback EasyCrypt goals adapter");
    register_goals (fun scope -> fallback_goals_of_scope scope)
  end


