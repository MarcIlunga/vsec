(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
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

open Protocol
open Protocol.LspWrapper
open Scheduler
open Types
open Thread
open Mutex

let Log log = Log.mk_log "executionManager"

(* EasyCrypt initialization flag *)
let easycrypt_initialized = ref false

(* Store the last raw output from the EasyCrypt -emacs process so that
   the DocumentManager can include it as messages in the proofView. *)
let last_easycrypt_raw_output : string ref = ref ""
let get_last_easycrypt_raw_output () = !last_easycrypt_raw_output

type feedback_message = Protocol.LspWrapper.DiagnosticSeverity.t * EasyCryptLocation.t option * string

type execution_status =
  | Success of EcLib.EcScope.scope option
  | Error of (EasyCryptLocation.t * string) * EcLib.EcScope.scope option (* State to use for resiliency *)

(* 🎯 HYBRID ARCHITECTURE: EasyCrypt Process Management *)
type easycrypt_process = {
  process: Unix.process_status option;
  stdin: Unix.file_descr option;
  stdout: Unix.file_descr option;
  stderr: Unix.file_descr option;
  mutable active: bool;
}

let global_easycrypt_process = ref None

(* Global background reader (hybrid) *)
let ec_output_mutex = Mutex.create ()
let ec_output_cond = Condition.create ()
let ec_output_buffer : Buffer.t = Buffer.create 16384
let ec_reader_stop = ref false
let ec_reader_thread : Thread.t option ref = ref None

let clear_ec_output_buffer () =
  Mutex.lock ec_output_mutex;
  Buffer.clear ec_output_buffer;
  Mutex.unlock ec_output_mutex

let snapshot_ec_output_buffer () : string =
  Mutex.lock ec_output_mutex;
  let s = Buffer.contents ec_output_buffer in
  Mutex.unlock ec_output_mutex; s

let signal_if_prompt () =
  if Pg_compat.has_prompt (Buffer.contents ec_output_buffer) then
    Condition.broadcast ec_output_cond

let start_easycrypt_reader_thread () =
  match !ec_reader_thread with
  | Some _ -> ()
  | None ->
    (match !global_easycrypt_process with
     | None -> ()
     | Some proc ->
       (match proc.stdout with
        | None -> ()
        | Some fd ->
          (try Unix.set_nonblock fd with _ -> ());
          ec_reader_stop := false;
          let th = Thread.create (fun () ->
            let chunk_size = 16384 in
            while (not !ec_reader_stop) do
              try
                let r, _, _ = Unix.select [fd] [] [] 0.1 in
                if r <> [] then (
                  let scratch = Bytes.create chunk_size in
                  let n = Unix.read fd scratch 0 chunk_size in
                  if n > 0 then (
                    Mutex.lock ec_output_mutex;
                    Buffer.add_subbytes ec_output_buffer scratch 0 n;
                    let _ = signal_if_prompt () in
                    Mutex.unlock ec_output_mutex
                  ) else Thread.delay 0.02
                ) else Thread.delay 0.02
              with _ -> Thread.delay 0.05
            done
          ) () in
          ec_reader_thread := Some th))

(* Spawn EasyCrypt process in -emacs mode for hybrid goal extraction *)
let spawn_easycrypt_process () =
  let spawn_with program argv : easycrypt_process option =
    try
      log (fun () -> Printf.sprintf "🚀 Spawning process: %s %s" program (String.concat " " (Array.to_list argv)));
      let (in_fd, out_fd) = Unix.pipe () in
      let (err_in_fd, err_out_fd) = Unix.pipe () in
      let (proc_in_fd, proc_out_fd) = Unix.pipe () in
      ignore (Unix.create_process program argv proc_in_fd out_fd err_out_fd);
      let proc = {
        process = None;
        stdin = Some proc_out_fd;
        stdout = Some in_fd;
        stderr = Some err_in_fd;
        active = true;
      } in
      Unix.close proc_in_fd;
      Unix.close out_fd;
      Unix.close err_out_fd;
      Some proc
    with exn ->
      log (fun () -> Printf.sprintf "❌ Failed spawning %s: %s" program (Printexc.to_string exn));
      None
  in
  (* 1) Respect explicit override via env var *)
  let try_env_override () =
    match Sys.getenv_opt "VSEC_EASYCRYPT" with
    | Some bin when String.length bin > 0 -> spawn_with bin [|bin; "cli"; "-emacs"|]
    | _ -> None
  in
  (* 2) Try easycrypt on PATH *)
  let try_plain_easycrypt () = spawn_with "easycrypt" [|"easycrypt"; "cli"; "-emacs"|] in
  (* 3) Fallback: use opam to provide environment *)
  let try_opam_exec_easycrypt () = spawn_with "opam" [|"opam"; "exec"; "--"; "easycrypt"; "cli"; "-emacs"|] in
  let res = match try_env_override () with
  | Some proc -> global_easycrypt_process := Some proc; log (fun () -> "✅ EasyCrypt spawned via VSEC_EASYCRYPT"); Some proc
  | None ->
    begin match try_plain_easycrypt () with
    | Some proc -> global_easycrypt_process := Some proc; log (fun () -> "✅ EasyCrypt spawned from PATH"); Some proc
    | None ->
      begin match try_opam_exec_easycrypt () with
      | Some proc -> global_easycrypt_process := Some proc; log (fun () -> "✅ EasyCrypt spawned via opam exec"); Some proc
      | None -> log (fun () -> "❌ Could not spawn EasyCrypt (PATH/VSEC_EASYCRYPT/opam exec all failed)"); None
      end
    end
  in
  (match res with Some _ -> start_easycrypt_reader_thread () | None -> ()); res

(* Send command to EasyCrypt process *)
let rec send_command_to_easycrypt cmd =
  match !global_easycrypt_process with
  | None ->
    log (fun () -> "⚠️ No EasyCrypt process available, attempting to spawn");
    (match spawn_easycrypt_process () with
     | Some proc -> send_command_to_easycrypt cmd
     | None -> None)
  | Some proc when not proc.active ->
    log (fun () -> "⚠️ EasyCrypt process not active");
    None
  | Some proc ->
    match proc.stdin with
    | None -> 
      log (fun () -> "❌ EasyCrypt process stdin not available");
      None
    | Some stdin_fd ->
      try
        let cmd_with_newline = cmd ^ "\n" in
        let bytes_written = Unix.write stdin_fd (Bytes.of_string cmd_with_newline) 0 (String.length cmd_with_newline) in
        log (fun () -> Printf.sprintf "📤 Sent %d bytes to EasyCrypt: %s" bytes_written cmd);
        Some ()
      with exn ->
        log (fun () -> Printf.sprintf "❌ Failed to send command to EasyCrypt: %s" (Printexc.to_string exn));
        None

(* Kill the EasyCrypt process *)
let kill_easycrypt_process () : unit =
  match !global_easycrypt_process with
  | None -> ()
  | Some proc ->
    (try Option.iter Unix.close proc.stdin with _ -> ());
    (try Option.iter Unix.close proc.stdout with _ -> ());
    (try Option.iter Unix.close proc.stderr with _ -> ());
    (* Ensure reader thread stops and buffers are cleared to avoid stale prompts/output *)
    (match !ec_reader_thread with
     | Some th -> ec_reader_stop := true; (try Thread.join th with _ -> ()); ec_reader_thread := None
     | None -> ());
    clear_ec_output_buffer ();
    last_easycrypt_raw_output := "";
    global_easycrypt_process := None

(* Read output from EasyCrypt process *)
let read_easycrypt_output () =
  match !global_easycrypt_process with
  | None -> ""
  | Some proc when not proc.active -> ""
  | Some proc ->
    match proc.stdout with
    | None -> ""
    | Some stdout_fd ->
      try
        let buffer = Bytes.create 16384 in
        let bytes_read = Unix.read stdout_fd buffer 0 16384 in
        let output = Bytes.sub_string buffer 0 bytes_read in
        log (fun () -> Printf.sprintf "📥 Read %d bytes from EasyCrypt: %s" bytes_read (String.escaped output));
        output
      with exn ->
        log (fun () -> Printf.sprintf "❌ Failed to read from EasyCrypt: %s" (Printexc.to_string exn));
        ""

(* Robust read: drain stdout until we see a prompt or timeout, with dynamic buffer and max cap *)
let read_easycrypt_output_until_prompt ?(timeout_s=0.0) ?(idle_wait_s=0.05) ?(chunk_size=16384) ?(max_bytes=1048576) () : string =
  match !global_easycrypt_process with
  | None -> ""
  | Some proc when not proc.active -> ""
  | Some proc ->
    begin match proc.stdout with
    | None -> ""
    | Some fd ->
      let buf = Buffer.create chunk_size in
      let deadline = if timeout_s > 0.0 then (Unix.gettimeofday () +. timeout_s) else infinity in
      (try Unix.set_nonblock fd with _ -> ());
      let rec loop () =
        if Unix.gettimeofday () > deadline then () else (
          let r, _, _ = Unix.select [fd] [] [] idle_wait_s in
          if r = [] then (
            (* No data ready; if we already have a prompt, stop *)
            if Pg_compat.has_prompt (Buffer.contents buf) then () else loop ()
          ) else (
            let scratch = Bytes.create chunk_size in
            (try
               let n = Unix.read fd scratch 0 chunk_size in
               if n > 0 then Buffer.add_subbytes buf scratch 0 n;
             with
             | Unix.Unix_error (Unix.EAGAIN, _, _) -> ()
             | exn -> log (fun () -> Printf.sprintf "⚠️ Non-blocking read error: %s" (Printexc.to_string exn)));
            if Buffer.length buf >= max_bytes then ()
            else if Pg_compat.has_prompt (Buffer.contents buf) then ()
            else loop ()
          )
        )
      in
      loop (); Buffer.contents buf
    end

(* 🎯 HYBRID GOAL EXTRACTION: Parse EasyCrypt -emacs output using Proof General patterns *)
type hybrid_goal = { hyps : string list; goal : string }

let parse_easycrypt_goals_from_output output : hybrid_goal list =
  log (fun () -> Printf.sprintf "🔍 Parsing EasyCrypt output for goals: %s" (String.escaped output));
  try
    let groups = Pg_compat.parse_goal_groups_from_output output in
    let goals_pairs =
      match groups.current with
      | (_ :: _ as gs) -> gs
      | [] -> (* Fallback to simple parser for older outputs *) Pg_compat.parse_goals_from_output output
    in
    goals_pairs
    |> List.map (fun (hyps, goal) -> { hyps; goal })
  with exn ->
    log (fun () -> Printf.sprintf "❌ Error parsing EasyCrypt output: %s" (Printexc.to_string exn));
    []

(* Execute command in EasyCrypt process and parse goals *)
let execute_with_goal_extraction cmd : hybrid_goal list =
  match send_command_to_easycrypt cmd with
  | None -> []
  | Some () ->
    (* Allow EasyCrypt to process and read until we see a prompt or timeout; robust draining *)
    (* Wait on the background buffer until we see a prompt or small idle delay *)
    let output =
      (try
         (* give it a moment to accumulate *)
         Unix.sleepf 0.02;
         let rec wait_while_no_prompt tries =
           if tries <= 0 then () else (
             Mutex.lock ec_output_mutex;
             let has = Pg_compat.has_prompt (Buffer.contents ec_output_buffer) in
             Mutex.unlock ec_output_mutex;
             if has then () else (Thread.delay 0.05; wait_while_no_prompt (tries - 1))
           ) in
         wait_while_no_prompt 40; (* ~2s max wait; can be increased or removed since reader persists *)
         snapshot_ec_output_buffer ()
       with _ -> snapshot_ec_output_buffer ())
    in
    if String.length output > 0 then (
      (* Also print raw output as a proofView message so the UI shows something *)
      log (fun () -> "📤 Hybrid RAW OUTPUT BEGIN\n" ^ output ^ "\n📤 Hybrid RAW OUTPUT END");
      last_easycrypt_raw_output := output;
      parse_easycrypt_goals_from_output output
    )
    else (
      log (fun () -> "⚠️ No output received from EasyCrypt process");
      []
    )

(* Hybrid replay: feed all sentences up to [id] to easycrypt -emacs, parsing goals at the end *)
(* (moved below SM definition to avoid forward-reference issues) *)

let success vernac_st = Success (Some vernac_st)
let error loc msg vernac_st = Error ((loc,msg), (Some vernac_st))

type sentence_id = int

type errored_sentence = (sentence_id * EasyCryptLocation.t option) option

module SM = Map.Make (Int) (* Using sentence_id as int instead of Stateid *)

type sentence_state =
  | Done of execution_status
  | Delegated of DelegationManager.job_handle * (execution_status -> unit) option
(* Hybrid replay function will be defined after the [state] record type *)


type delegation_mode =
  | CheckProofsInMaster
  | SkipProofs
  | DelegateProofsToWorkers of { number_of_workers : int }

type options = {
  delegation_mode : delegation_mode;
  (* completion_options : Settings.Completion.t; - commented out for EasyCrypt *)
  enableDiagnostics : bool
}

let default_options = {
  delegation_mode = CheckProofsInMaster;
  (* completion_options = ... - removed for EasyCrypt *)
  enableDiagnostics = true;
}

let doc_id = ref (-1)
let fresh_doc_id () = incr doc_id; !doc_id

type document_id = int

type rocq_feedback_listener = int

type delegated_task = { 
  terminator_id: sentence_id;
  opener_id: sentence_id;
  (* proof_using: Vernacexpr.section_subset_expr; - commented out for EasyCrypt *)
  last_step_id: sentence_id option; (* only for setting a proof remotely *)
  tasks: executable_sentence list;
}
(* Hybrid replay: feed all sentences up to [id] to easycrypt -emacs, parsing goals at the end *)
let hybrid_replay_for_sentence st _document _id : state * bool = st, false


type prepared_task =
  | PSkip of { id: sentence_id; error: string option }
  | PBlock of { id: sentence_id; synterp : EcLib.EcScope.scope; error: string * string }
  | PExec of executable_sentence
  | PQuery of executable_sentence
  | PDelegate of delegated_task


type state = {
  initial : EcLib.EcScope.scope;
  of_sentence : (sentence_state * feedback_message list) SM.t;
  todo: prepared_task list; (* execution queue *)

  (* EasyCrypt: Store executed scopes for context retrieval *)
  executed_scopes : EcLib.EcScope.scope SM.t;

  (* Hybrid: store last proof view (JSON) per executed sentence *)
  hybrid_proofs : Yojson.Safe.t SM.t;

  (* ugly stuff to correctly dispatch Rocq feedback *)
  doc_id : document_id; (* unique number used to interface with Rocq's Feedback *)
  rocq_feeder : rocq_feedback_listener;
  sel_feedback_queue : (int * sentence_id * feedback_message) Queue.t;
  sel_cancellation_handle : Sel.Event.cancellation_handle;
  overview: exec_overview;
  easycrypt_reader_thread: Thread.t option;
  easycrypt_reader_stop: bool ref;
}

let get_id_of_executed_task task =
  match task with
  | PSkip {id} -> id
  | PBlock {id} -> id
  | PExec {id} -> id
  | PQuery {id} -> id
  | PDelegate {terminator_id} -> terminator_id

(* Hybrid replay function defined later, after [set_hybrid_proof] *)

let print_exec_overview overview =
  let {processing; processed; prepared } = overview in
  log (fun () -> "--------- Prepared ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) prepared;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processing ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processing;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processed ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processed;
  log (fun () -> "-------------------------------------")


let print_exec_overview_of_state st = print_exec_overview st.overview
  
let options = ref default_options

let set_options o = options := o
let set_default_options () = options := default_options
let is_diagnostics_enabled () = !options.enableDiagnostics

let get_options () = !options

module ProofJob = struct
  type update_request =
    | UpdateExecStatus of sentence_id * execution_status
    | AppendFeedback of int * Types.sentence_id * (DiagnosticSeverity.t * EasyCryptLocation.t option * string)
  let appendFeedback (rid,sid) fb = AppendFeedback(rid,sid,fb)

  type t = {
    tasks : executable_sentence list;
    initial_vernac_state : EcLib.EcScope.scope;
    doc_id : int;
    terminator_id : sentence_id;
  }
  let name = "proof"
  let binary_name = "vsrocqtop_proof_worker.opt"
  let initial_pool_size = 1

end

module ProofWorker = DelegationManager.MakeWorker(ProofJob)

type event =
  | LocalFeedback of (int * sentence_id * feedback_message) Queue.t * (int * sentence_id * feedback_message) list
  | ProofWorkerEvent of ProofWorker.delegation

type events = event Sel.Event.t list
let pr_event = function
  | LocalFeedback _ -> "LocalFeedback"
  | ProofWorkerEvent event -> ProofWorker.pr_event event

let inject_proof_event = Sel.Event.map (fun x -> ProofWorkerEvent x)
let inject_proof_events st l =
  (st, List.map inject_proof_event l)

let interp_error_recovery strategy st : EcLib.EcScope.scope =
  match strategy with
  | RSkip -> st
  | RAdmitted -> st (* Return current state unchanged - no error recovery in EasyCrypt yet *)

(* Helper function to check if command contains keyword *)
let contains_keyword command keyword =
  let re = Str.regexp (".*\\b" ^ keyword ^ "\\b.*") in
  Str.string_match re command 0

(* 🎯 Phase 8.1.2: EasyCrypt Command Execution - RESTORED! *)
(* Ensure EasyCrypt command system is initialized before any processing *)
let ensure_easycrypt_initialized () =
  if not !easycrypt_initialized then (
    log (fun () -> "Initializing EasyCrypt commands system (ensure) ...");
    try
      let checkmode = {
        EcLib.EcCommands.cm_checkall  = false;
        EcLib.EcCommands.cm_timeout   = 3;
        EcLib.EcCommands.cm_cpufactor = 1;
        EcLib.EcCommands.cm_nprovers  = 4;
        EcLib.EcCommands.cm_provers   = None;
        EcLib.EcCommands.cm_profile   = false;
        EcLib.EcCommands.cm_iterate   = false;
      } in
      EcLib.EcCommands.initialize ~restart:false ~undo:true ~boot:false ~checkmode;
      easycrypt_initialized := true
    with exn ->
      log (fun () -> Printf.sprintf "Failed to initialize EasyCrypt (ensure): %s" (Printexc.to_string exn))
  )

(* Extract a global_action from a parsed EcLib program, if any *)
let extract_action_from_prog (prog: EcLib.EcParsetree.prog) : (EcLib.EcParsetree.global_action EcLib.EcLocation.located) option =
  try
    let open EcLib in
    let open EcParsetree in
    match EcLocation.unloc prog with
    | P_Prog (globals, _terminate) ->
      begin match globals with
      | [] -> None
      | g :: _ -> Some g.gl_action
      end
  with _ -> None

let starts_with (s:string) (prefix:string) =
  let ls = String.length s and lp = String.length prefix in
  ls >= lp && String.sub s 0 lp = prefix

let build_action_from_string (s:string) : (EcLib.EcParsetree.global_action EcLib.EcLocation.located) option =
  let open EcLib in
  let open EcParsetree in
  let open EcLocation in
  let sl = String.lowercase_ascii (String.trim s) in
  if starts_with sl "proof" then
    Some (mk_loc _dummy (Gtactics `Proof))
  else if starts_with sl "qed" then
    Some (mk_loc _dummy (Gsave (mk_loc _dummy `Qed)))
  else if starts_with sl "admit" then
    Some (mk_loc _dummy (Gsave (mk_loc _dummy `Admit)))
  else None

(* Helpers to classify EasyCrypt -emacs raw outputs *)
let is_prompt_only (s:string) : bool = Pg_compat.is_prompt_only s

let contains_current_goal (s:string) : bool = Pg_compat.contains_current_goal s

let contains_no_more_goals (s:string) : bool = Pg_compat.contains_no_more_goals s

let is_meaningful_raw_output (s:string) : bool =
  String.length (String.trim s) > 0 && not (is_prompt_only s) && (contains_current_goal s || contains_no_more_goals s)

let interp_ast ~doc_id ~state_id ~st ~error_recovery ?(ec_action:EcLib.EcParsetree.global_action EcLib.EcLocation.located option) ast =
  log (fun () -> Printf.sprintf "EasyCrypt command execution for sentence %d: %s" state_id ast);
  
  (* Trim whitespace from AST *)
  let ast_trimmed = String.trim ast in
  
  if String.length ast_trimmed = 0 then (
    (* Empty command - return current state unchanged *)
    st, success st, []
  ) else
  try
    (* Ensure initialized and execute the EasyCrypt sentence using EcLib if we have a parsed action *)
    ensure_easycrypt_initialized ();
    let action = match ec_action with Some a -> Some a | None -> build_action_from_string ast_trimmed in
    let new_scope =
      match action with
      | Some action ->
        log (fun () -> "⚡ EasyCrypt: Processing command via EcCommands.process_internal (AST)");
        (* Use process_internal to deterministically produce the next scope from the given one *)
        (try EcLib.EcCommands.process_internal EcLib.EcCommands.loader st action with _ -> st)
      | None ->
        log (fun () -> "⚠️ No EcLib action available; skipping execution");
        st
    in
    (* Success: return updated scope; feedback events deferred for now *)
    new_scope, success new_scope, []
    
  with
  | exn ->
    let error_msg = Printexc.to_string exn in
    let error_location = EasyCryptLocation.{ start_line = 0; start_col = 0; end_line = 0; end_col = String.length ast } in
    log (fun () -> Printf.sprintf "EasyCrypt execution error for sentence %d: %s" state_id error_msg);
    
    (* Implement error recovery using strategy *)
    let fallback_state = interp_error_recovery error_recovery st in
    let error_feedback = [(state_id, ((), Some error_location, error_msg))] in
    
    (* TODO: Convert error_feedback to proper Sel.Event.t list *)
    fallback_state, Error ((error_location, error_msg), Some fallback_state), [] (* Simplified for now *)

(* This adapts the Future API with our event model *)
(* [%%if rocq = "8.18"] - commented out for EasyCrypt
let definition_using e s ~fixnames:_ ~using ~terms =
  Proof_using.definition_using e s ~using ~terms
[%%elif rocq = "8.19"] *)
(* let definition_using = Proof_using.definition_using
[%%endif] - commented out for EasyCrypt *)


let interp_qed_delayed ~proof_using ~state_id ~st =
  (* Simplified stub for EasyCrypt - replaces entire Coq proof delegation system *)
  log (fun () -> Printf.sprintf "EasyCrypt qed stub for sentence %d" state_id);
  let assign _proof = () in (* Stub function that does nothing *)
  st, success st, assign

let cut_overview task state document =
  let range = match task with
  | PDelegate { terminator_id } -> Document.range_of_id_with_blank_space document terminator_id
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } ->
    Document.range_of_id_with_blank_space document id
  in
  let {prepared; processing; processed} = state.overview in
  let prepared = RangeList.cut_from_range range prepared in
  let processing = RangeList.cut_from_range range processing in
  let overview = {prepared; processing; processed} in
  {state with overview}

let update_processed_as_Done s range overview =
  let {prepared; processing; processed} = overview in
  match s with
  | Success _ ->
    let processed = RangeList.insert_or_merge_range range processed in
    let processing = RangeList.remove_or_truncate_range range processing in
    let prepared = RangeList.remove_or_truncate_range range prepared in
    {prepared; processing; processed}
  | Error _ ->
    let processing = RangeList.remove_or_truncate_range range processing in
    let prepared = RangeList.remove_or_truncate_range range prepared in
    {prepared; processing; processed}

let update_processed id state document =
  let range = Document.range_of_id_with_blank_space document id in
  match SM.find id state.of_sentence with
  | (s, _) ->
    begin match s with
    | Done s -> 
      let overview = update_processed_as_Done s range state.overview in
      {state with overview}
    | _ -> assert false (* delegated sentences born as such, cannot become it later *)
    end
  | exception Not_found ->
    log (fun () -> "Trying to get overview with non-existing state id " ^ string_of_int id);
    state

let id_of_first_task ~default = function
  | [] -> default
  | { id } :: _ -> id

let id_of_last_task ~default l =
  id_of_first_task ~default (List.rev l)

let update_processing task state document =
  let {processing; prepared} = state.overview in
  match task with
  | PDelegate { opener_id; terminator_id; tasks } ->
    let proof_opener_id = id_of_first_task ~default:opener_id tasks in
    let proof_closer_id = id_of_last_task ~default:terminator_id tasks in
    let proof_begin_range = Document.range_of_id_with_blank_space document proof_opener_id in
    let proof_end_range = Document.range_of_id_with_blank_space document proof_closer_id in
    let range = Range.create ~end_:proof_end_range.end_ ~start:proof_begin_range.start in
    (* When a job is delegated we shouldn't merge ranges (to get the proper progress report) *)
    let processing = List.append processing [ range ] in 
    let prepared = RangeList.remove_or_truncate_range range prepared in
    let overview = {state.overview with prepared; processing} in
    {state with overview}
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } ->
    let range = Document.range_of_id_with_blank_space document id in
    let processing = RangeList.insert_or_merge_range range processing in
    let prepared = RangeList.remove_or_truncate_range range prepared in
    let overview = {state.overview with processing; prepared} in
    {state with overview}

let update_prepared task document state =
  let {prepared} = state.overview in
  match task with
  | PDelegate { opener_id; terminator_id; tasks } ->
    let proof_opener_id = id_of_first_task ~default:opener_id tasks in
    let proof_closer_id = id_of_last_task ~default:terminator_id tasks in
    let proof_begin_range = Document.range_of_id_with_blank_space document proof_opener_id in
    let proof_end_range = Document.range_of_id_with_blank_space document proof_closer_id in
    let range = Range.create ~end_:proof_end_range.end_ ~start:proof_begin_range.start in
    (* When a job is delegated we shouldn't merge ranges (to get the proper progress report) *)
    let prepared = List.append prepared [ range ] in
    let overview = {state.overview with prepared} in
    {state with overview}
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } ->
    let range = Document.range_of_id_with_blank_space document id in
    let prepared = RangeList.insert_or_merge_range range prepared in
    let overview = {state.overview with prepared} in
    {state with overview}

let update_overview task state document =
  let state = 
  match task with
  | PDelegate { terminator_id } ->
    let range = Document.range_of_id_with_blank_space document terminator_id in
    let {prepared} = state.overview in
    let prepared = RangeList.remove_or_truncate_range range prepared in
    let overview = update_processed_as_Done (Success None) range state.overview in
    let overview = {overview with prepared} in
    {state with overview}
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } ->
    update_processed id state document
  in
  match state.todo with
  | [] -> state
  | next :: _ -> update_processing next state document


let build_prepared_overview state document =
  List.fold_right (fun task st -> update_prepared task document st) state.todo state

let build_processed_overview state document =
  let sentence_ids = SM.bindings state.of_sentence in
  let sentence_ids = List.map (fun x -> fst x) sentence_ids in
  List.fold_right (fun id st -> update_processed id st document) sentence_ids state

let reset_overview st document =
  let overview = {processed=[]; prepared=[]; processing=[]} in
  let st = build_processed_overview {st with overview} document in
  build_prepared_overview st document

let prepare_overview st prepared =
  let overview = {st.overview with prepared} in
  {st with overview}

let overview st = st.overview

let overview_until_range st range =
  let find_final_range l = List.find_opt (fun (r: Range.t) -> Range.included ~in_:r range) l in
  let {processed; processing; prepared} = st.overview in
  let final_range = find_final_range processed  in
  match final_range with
  | None ->
    let final_range = find_final_range processing in
    begin match final_range with
    | None -> { processed; processing; prepared }
    | Some { start } ->
      let processing = (List.filter (fun (r: Range.t) -> not @@ Range.included ~in_:r range) processing) in
      let processing = List.append processing [Range.create ~start:start ~end_:range.end_] in
      {processing; processed; prepared}
    end
  | Some { start } ->
    let processed = (List.filter (fun (r: Range.t) -> (not @@ Range.included ~in_:r range) && (Position.compare r.start range.end_ <= 0)) processed) in
    let processed = List.append processed [Range.create ~start:start ~end_:range.end_] in
    print_exec_overview {processing; processed;prepared};
    { processing; processed; prepared }


let update_all id v fl state =
  { state with of_sentence = SM.add id (v, fl) state.of_sentence }
;;
let update state id v =
  let fl = try snd (SM.find id state.of_sentence) with Not_found -> [] in
  update_all id (Done v) fl state
;;

let local_feedback feedback_queue : event Sel.Event.t =
  Sel.On.queue_all ~name:"feedback" ~priority:PriorityManager.feedback feedback_queue (fun x xs -> LocalFeedback(feedback_queue, x :: xs))

let install_feedback_listener doc_id send =
  (* Entire feedback system commented out for EasyCrypt *)
  ()

let init vernac_state =
  let doc_id = fresh_doc_id () in
  let sel_feedback_queue = Queue.create () in
  let rocq_feeder = install_feedback_listener doc_id (fun x -> Queue.push x sel_feedback_queue) in
  let event = local_feedback sel_feedback_queue in
  let sel_cancellation_handle = Sel.Event.get_cancellation_handle event in
  {
    initial = vernac_state;
    of_sentence = SM.empty;
    todo = [];
    executed_scopes = SM.empty;
    hybrid_proofs = SM.empty;
    doc_id;
    rocq_feeder = 0; (* rocq_feeder placeholder *)
    sel_feedback_queue;
    sel_cancellation_handle;
    overview = empty_overview;
    easycrypt_reader_thread = None;
    easycrypt_reader_stop = ref false;
  },
  event

(* called by the forked child. Since the Feedback API is imperative, the
   feedback pipes have to be modified in place *)
let feedback_cleanup { rocq_feeder; sel_feedback_queue; sel_cancellation_handle } =
  (* Feedback.del_feeder rocq_feeder; - disabled for EasyCrypt *)
  Queue.clear sel_feedback_queue;
  Sel.Event.cancel sel_cancellation_handle

let handle_feedback state (_,id, fb) =
  match fb with
  | (_, _, _, msg) ->
    begin match SM.find id state.of_sentence with
    | (s,fl) -> update_all id s (fl @ [(Lsp.Types.DiagnosticSeverity.Error, None, "feedback message")]) state
    | exception Not_found -> 
        log (fun () -> "Received feedback on non-existing state id " ^ string_of_int id ^ ": " ^ msg);
        state
    end 

let handle_event event state =
  match event with
  | LocalFeedback (q,l) ->
      None, Some (List.fold_left (fun st (_, id, _) -> st) state l), [local_feedback q]
  | ProofWorkerEvent event ->
      let update, events = ProofWorker.handle_event event in
      let state, id =
        match update with
        | None -> None, None
        | Some (ProofJob.AppendFeedback(x,id,fb)) ->
            Some (handle_feedback state (x,id,(Types.DiagnosticSeverity.Error, None, (), "feedback"))), None
        | Some (ProofJob.UpdateExecStatus(id,v)) ->
            match SM.find id state.of_sentence, v with
            | (Delegated (_,completion), fl), _ ->
                (match completion with Some f -> f v | None -> ());
                Some (update_all id (Done v) fl state), Some id
            | (Done (Success s), fl), Error (err, _) ->
                (* This only happens when a Qed closing a delegated proof
                   receives an updated by a worker saying that the proof is
                   not completed *)
                Some (update_all id (Done (Error (err,s))) fl state), Some id
            | (Done _, _), _ -> None, Some id
            | exception Not_found -> None, None (* TODO: is this possible? *)
      in
      let state, events = inject_proof_events state events in
      id, state, events

let find_fulfilled_opt x m =
  try
    let ss,_ = SM.find x m in
    match ss with
    | Done x -> Some x
    | Delegated _ -> None
  with Not_found -> None


let exec_error_of_execution_status id v = match v with
  | Success _ -> None
  | Error ((loc, _), _) -> Some (id, Some loc)

let get_vs_and_exec_error st id =
  match fst @@ SM.find id st.of_sentence with
  | Done (Success (Some vs) as es) -> vs, exec_error_of_execution_status id es
  | Done (Error (_,Some vs) as es) -> vs, exec_error_of_execution_status id es
  | _ -> failwith "get_vs_and_exec_error call should be protected with is_locally_executed"
  | exception Not_found -> assert false

let is_locally_executed st id =
  match find_fulfilled_opt id st.of_sentence with
  | Some (Success (Some _) | Error (_, Some _)) -> true
  | _ -> false

let is_remotely_executed st id =
  match find_fulfilled_opt id st.of_sentence with
  | Some (Success None | Error (_, None)) -> true
  | _ -> false
  
  
let jobs : (DelegationManager.job_handle * Sel.Event.cancellation_handle * ProofJob.t) Queue.t = Queue.create ()

(* TODO: kill all Delegated... *)
let destroy st =
  feedback_cleanup st;
  Queue.iter (fun (h,c,_) -> DelegationManager.cancel_job h; Sel.Event.cancel c) jobs
  ; (match st.easycrypt_reader_thread with
    | Some th ->
        st.easycrypt_reader_stop := true;
        (try Thread.join th with _ -> ());
        ()
    | None -> ())


let last_opt l = 
  match List.rev l with
  | [] -> None
  | last :: _ -> Some last.id

let prepare_task task : prepared_task list =
  match task with
  | Skip { id; error } -> [PSkip { id; error }]
  | Block { id; synterp; error } -> 
      let error_str = match error with
        | (None, msg) -> ("(no location)", msg)
        | (Some loc, msg) -> (Types.EasyCryptLocation.string_of_location loc, msg)
      in
      [PBlock {id; synterp; error = error_str}]
  | Exec e -> [PExec e]
  | Query e -> [PQuery e]
  | OpaqueProof { terminator; opener_id; tasks; proof_using} ->
      match !options.delegation_mode with
      | DelegateProofsToWorkers _ ->
          log (fun () -> "delegating proofs to workers");
          let last_step_id = last_opt tasks in
          [PDelegate {terminator_id = terminator.id; opener_id; last_step_id; tasks}]
      | CheckProofsInMaster ->
          log (fun () -> "running the proof in master as per config");
          List.map (fun x -> PExec x) tasks @ [PExec terminator]
      | SkipProofs ->
          log (fun () -> Printf.sprintf "skipping proof made of %d tasks" (List.length tasks));
          [PExec terminator]

let id_of_prepared_task = function
  | PSkip { id } -> id
  | PBlock { id } -> id
  | PExec ex -> ex.id
  | PQuery ex -> ex.id
  | PDelegate { terminator_id } -> terminator_id

let purge_state = function
  | Success _ -> Success None
  | Error(e,_) -> Error (e,None)

(* TODO move to proper place *)
let worker_execute ~doc_id ~send_back (vs,events) { id; ast; synterp; error_recovery } =
  (* In EasyCrypt, use the synterp state directly since EcScope doesn't have field updates like Coq *)
  let vs = synterp in
  log (fun () -> "worker interp " ^ Document.sentence_ido_string id);
  let vs, v, ev = interp_ast ~doc_id ~state_id:id ~st:vs ~error_recovery ast in
  send_back (ProofJob.UpdateExecStatus (id,purge_state v));
  (vs, events @ ev)

(* The execution of Qed for a non-delegated proof checks the proof is completed.
   When the proof is delegated this step is performed by the worker, which
   sends back an update on the Qed sentence in case the proof is unfinished *)
(* COMMENTED OUT - Complex Coq proof management function - TODO: Adapt for EasyCrypt
let worker_ensure_proof_is_over vs send_back terminator_id =
  let f = Declare.Proof.close_proof in
  let open Vernacstate in (* shadows Declare *)
  let { Interp.lemmas } = vs.interp in
  match lemmas with
  | None -> assert false
  | Some lemmas ->
      let proof = Vernacstate.LemmaStack.get_top lemmas in
      (* Simplified for EasyCrypt - complex Coq proof handling commented out *)
      log (fun () -> "EasyCrypt proof stub - skipping complex proof handling")
*)

(* Minimal stub for EasyCrypt - TODO: implement proper proof completion check *)
let worker_ensure_proof_is_over vs send_back terminator_id =
  log (fun () -> "worker_ensure_proof_is_over: minimal stub for EasyCrypt");
  (* For now, just assume the proof is complete *)
  ()

let worker_main { ProofJob.tasks; initial_vernac_state = vs; doc_id; terminator_id } ~send_back =
  try
    let vs, _ = List.fold_left (worker_execute ~doc_id ~send_back) (vs,[]) tasks in
    worker_ensure_proof_is_over vs send_back terminator_id;
    flush_all ();
    (* Use Thread.Exit to terminate worker thread properly *)
    raise Thread.Exit
  with e ->
    let message = Printexc.to_string e in
    log (fun () -> "======================= worker exception ===========================");
    log (fun () -> message);
    log (fun () -> "==========================================================");
    raise Thread.Exit

(* Hybrid helpers need to be defined before use in execute_task *)
let set_hybrid_proof st id proof_json =
  { st with hybrid_proofs = SM.add id proof_json st.hybrid_proofs }

let hybrid_proof_for_sentence st id =
  try Some (SM.find id st.hybrid_proofs) with Not_found -> None

(* Hybrid replay: feed all sentences up to [id] to easycrypt -emacs, parsing goals at the end *)
let hybrid_replay_for_sentence st document id : state * bool =
  let sentences = Document.Internal.sentences_in_order document in
  let rec feed acc_st fed_any = function
    | [] -> acc_st, fed_any
    | s :: rest ->
      let acc_st, fed_any =
        if s.Document.id <= id then (
          let text = Document.Internal.string_of_sentence s in
          let _ = execute_with_goal_extraction text in
          acc_st, true
        ) else (acc_st, fed_any)
      in
      feed acc_st fed_any rest
  in
  let st', fed = feed st false sentences in
  if not fed then st', false else (
    let output = get_last_easycrypt_raw_output () in
    let goals = parse_easycrypt_goals_from_output output in
    if goals = [] then st', false else (
      let uri_str = "file://unknown" in
      let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
      let goals_json =
        `List (List.mapi (fun idx (g:hybrid_goal) ->
          `Assoc [ ("id", `Int (idx + 1)); ("hypotheses", `List (List.map (fun h -> `String h) g.hyps)); ("goal", `String g.goal) ]) goals)
      in
      let progress = Pg_compat.progress_of_output output in
      let proof_json : Yojson.Safe.t = `Assoc [
        ("goals", goals_json);
        ("shelvedGoals", `List []);
        ("givenUpGoals", `List []);
        ("unfocusedGoals", `List []);
        ("navigation", `Null);
        ("current_lemma", `Null);
        ("proof_progress", `Float progress)
      ] in
      let notif_json : Yojson.Safe.t = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "prover/proofView");
        ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json); ("messages", `List []) ])
      ] in
      let st'' = set_hybrid_proof st' id notif_json
      in
      st'', true
    )
  )

(* Hybrid replay function is defined after the state type; see below. *)

let execute_task st document (vs, events, interrupted) task =
  if interrupted then begin
    let st = update st (id_of_prepared_task task) (Error ((Types.EasyCryptLocation.dummy,"interrupted"), None)) in
    let todo = [] in
    ({st with todo}, vs, events, true, None)
  end else
    try
      match task with
      | PBlock { id; synterp; error = err} ->
        (* Do not execute blocks; just register error on current scope *)
        let vs, st_with_scope = synterp, st in
        let (loc_str, pp) = err in
        let v = error EasyCryptLocation.dummy pp vs in
        let parse_error = Some (id, Some EasyCryptLocation.dummy) in
        let st = update st_with_scope id v in
        (st, vs, events, false, parse_error)
      | PSkip { id; error = err } ->
          let v = match err with
            | None -> success vs
            | Some msg -> error EasyCryptLocation.dummy msg vs
          in
          let st = update st id v in
          (st, vs, events, false, None)
      | PExec ({ id; ast; synterp = _; error_recovery; ec_prog; _ } as _exec) ->
        (* Execute hybrid first for visible goals; also run embedded when possible to maintain scope *)
        let _hybrid_goals = execute_with_goal_extraction ast in
        let st =
          match _hybrid_goals with
          | [] ->
            (* Only send a message if the raw output is meaningful (not just prompt) *)
            let raw_out = get_last_easycrypt_raw_output () in
            if not (is_meaningful_raw_output raw_out) then st
            else
              let uri_str = Lsp.Types.DocumentUri.to_string (Lsp.Types.DocumentUri.of_path "") in
              let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
              let progress = Pg_compat.progress_of_output raw_out in
              let proof_json : Yojson.Safe.t = `Assoc [
                ("goals", `List []);
                ("shelvedGoals", `List []);
                ("givenUpGoals", `List []);
                ("unfocusedGoals", `List []);
                ("navigation", `Null);
                ("current_lemma", `Null);
                ("proof_progress", `Float progress)
              ] in
              let messages_json = `List [ `Assoc [("level", `String "info"); ("text", `String raw_out)] ] in
              let notif_json : Yojson.Safe.t = `Assoc [
                ("jsonrpc", `String "2.0");
                ("method", `String "prover/proofView");
                ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json); ("messages", messages_json) ])
              ] in
              let st = set_hybrid_proof st id notif_json in
              st
          | goals ->
            (* Build a minimal proofView notification JSON and store for SendProofView *)
            let uri_str = Lsp.Types.DocumentUri.to_string (Lsp.Types.DocumentUri.of_path "") in
            let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
            (* Map parsed hybrid goals to proofView JSON structure *)
            let goals_json =
              `List (List.mapi (fun idx g ->
                `Assoc [
                  ("id", `Int (idx + 1));
                  ("hypotheses", `List (List.map (fun h -> `String h) g.hyps));
                  ("goal", `String g.goal)
                ]) goals)
            in
            let progress = Pg_compat.progress_of_output (get_last_easycrypt_raw_output ()) in
            let proof_json : Yojson.Safe.t = `Assoc [
              ("goals", goals_json);
              ("shelvedGoals", `List []);
              ("givenUpGoals", `List []);
              ("unfocusedGoals", `List []);
              ("navigation", `Null);
              ("current_lemma", `Null);
              ("proof_progress", `Float progress)
            ] in
            (* When goals are parsed, do not echo raw output in messages to avoid duplication *)
            let messages_json = `List [] in
            let notif_json : Yojson.Safe.t = `Assoc [
              ("jsonrpc", `String "2.0");
              ("method", `String "prover/proofView");
              ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json); ("messages", messages_json) ])
            ] in
            let st = set_hybrid_proof st id notif_json in
            st
        in
        let ec_action =
          match ec_prog with
          | None -> None
          | Some prog -> extract_action_from_prog prog
        in
        let vs, v, ev = interp_ast ~doc_id:st.doc_id ~state_id:id ~st:vs ~error_recovery ?ec_action ast in
              let st = update st id v in
        let st = { st with executed_scopes = SM.add id vs st.executed_scopes } in
              let exec_error = exec_error_of_execution_status id v in
          (st, vs, events @ ev, false, exec_error)
      | PQuery ({ id; ast; synterp = _; error_recovery; ec_prog; _ } as _query) ->
        let ec_action =
          match ec_prog with
          | None -> None
          | Some prog -> extract_action_from_prog prog
        in
        let vs, v, ev = interp_ast ~doc_id:st.doc_id ~state_id:id ~st:vs ~error_recovery ?ec_action ast in
          let st = update st id v in
        let st = { st with executed_scopes = SM.add id vs st.executed_scopes } in
          (st, vs, events @ ev, false, None)
      | PDelegate { terminator_id; opener_id; last_step_id; tasks } ->
          begin match find_fulfilled_opt opener_id st.of_sentence with
          | Some (Success _) ->
            let job =  { ProofJob.tasks; initial_vernac_state = vs; doc_id = st.doc_id; terminator_id } in
            let job_id = DelegationManager.mk_job_handle (0,terminator_id) in
            (* The proof was successfully opened *)
            let last_vs, _v, assign = interp_qed_delayed ~state_id:terminator_id ~proof_using:None ~st:vs in
            let complete_job status =
              try match status with
              | Success None ->
                log (fun () -> "Resolved future (without sending back the witness)");
                assign (`Exn (Failure "no proof", Printexc.get_raw_backtrace ()))
              | Success (Some vernac_st) ->
                let f proof =
                  log (fun () -> "Resolved future");
                  assign (`Val proof) (* Simplified for EasyCrypt *)
                in
                (* Simplified for EasyCrypt - skip complex Coq lemma stack handling *)
                f ()
              | Error ((loc,err),_) ->
                  log (fun () -> "Aborted future");
                  assign (`Exn (Failure err, Printexc.get_raw_backtrace ()))
              with exn ->
                assign (`Exn (Failure("error closing proof"), Printexc.get_raw_backtrace ()))
            in
            let st = update st terminator_id (success last_vs) in
            let st = List.fold_left (fun st id ->
               if Option.equal Int.equal (Some id) last_step_id then
                 update_all id (Delegated (job_id,Some complete_job)) [] st
               else
                 update_all id (Delegated (job_id,None)) [] st)
               st (List.map (fun { id } -> id) tasks) in
            let e =
                ProofWorker.worker_available ~jobs
                  ~fork_action:worker_main
                  ~feedback_cleanup:(fun () -> feedback_cleanup st)
                in
              Queue.push (job_id, Sel.Event.get_cancellation_handle e, job) jobs;
              (* EasyCrypt stub - proof delegation events not implemented yet *)
              (st, last_vs, events, false, None)
          | _ ->
            (* If executing the proof opener failed, we skip the proof *)
            let st = update st terminator_id (success vs) in
            (st, vs,events,false, None)
          end
    with Sys.Break ->
      let st = update st (id_of_prepared_task task) (Error ((Types.EasyCryptLocation.dummy,"interrupted"), None)) in
      (st, vs, events, true, None)

let execute st document (vs, events, interrupted) task block_on_first_error : (prepared_task option * state * EcLib.EcScope.scope * event Sel.Event.t list * errored_sentence) =
  let st, vst_for_next_todo, events, _, exec_error =
    execute_task st document (vs, events, interrupted) task in
  match block_on_first_error, exec_error with
  | false, _ | _, None ->
    let st = update_overview task st document in
    let next, st = match st.todo with
      | [] -> None, st
      | task :: todo -> Some task, { st with todo }
    in next, st, vst_for_next_todo, events, None
  | true, Some _ ->
    let st = cut_overview task st document in
    let st = { st with todo=[]} in
    None, st, vst_for_next_todo, events, exec_error


let build_tasks_for document sch st id block =
  let rec build_tasks id tasks st =
    begin match find_fulfilled_opt id st.of_sentence with
    | Some (Success (Some vs)) ->
      (* We reached an already computed state *)
      log (fun () -> "Reached computed state " ^ Document.sentence_ido_string id);
      vs, tasks, st, None
    | Some (Error((loc, _), Some vs)) ->
      (* We try to be resilient to an error *)
      log (fun () -> "Error resiliency on state " ^ Document.sentence_ido_string id);
      vs, tasks, st, Some (id, Some loc)
    | _ ->
      log (fun () -> "Non (locally) computed state " ^ Document.sentence_ido_string id);
      let (base_id, task) = task_for_sentence sch id in
      begin match base_id with
      | None -> (* task should be executed in initial state *)
        st.initial, task :: tasks, st, None
      | Some base_id ->
        build_tasks base_id (task::tasks) st
      end
    end
  in
  let rec build_prepared_overview tasks state =
    begin match tasks with
    | [] -> state
    | task :: l -> build_prepared_overview l (update_prepared task document state)
    end
  in
  let vs, tasks, st, error_id = build_tasks id [] st in
  match error_id, block with
  | _, false | None, _ ->
    let todo = List.concat_map prepare_task tasks in
    let task, st = match todo with
      | task :: todo ->
        let st = {st with todo} in
        let st = build_prepared_overview todo st in
        Some task, st
      | [] ->
        None, {st with todo}
      in
      vs, st, task, None
  | Some id, true ->
    vs, {st with todo=[]}, None, Some id

let all_errors st =
  List.fold_left (fun acc (id, (p,_)) ->
    match p with
    | Done (Error ((loc,e), st_opt)) -> (id,(Some loc,e,None)) :: acc (* EasyCrypt - no quickfix, 3-tuple format *)
    | _ -> acc)
    [] @@ SM.bindings st.of_sentence

let error st id =
  match SM.find_opt id st.of_sentence with
  | Some (Done (Error ((loc,msg),_)), _) -> Some (Some loc, msg)
  | _ -> None

let feedback st id =
  match SM.find_opt id st.of_sentence with
  | None -> []
  | Some (_st, l) -> l

let all_feedback st =
  List.fold_left (fun acc (id, (_,l)) -> List.map (fun x -> (id, x)) l @ acc) [] @@ SM.bindings st.of_sentence

let shift_overview st ~before ~after ~start ~offset =
  let shift_loc loc_start loc_end =
    if loc_start >= start then (loc_start + offset, loc_end + offset)
    else if loc_end > start then (loc_start, loc_end + offset)
    else (loc_start, loc_end)
  in
  let shift_range range =
    let r_start = RawDocument.loc_of_position before range.Range.start in
    let r_stop = RawDocument.loc_of_position before range.Range.end_ in
    let r_start', r_stop' = shift_loc r_start r_stop in
    Range.create ~start:(RawDocument.position_of_loc after r_start') ~end_:(RawDocument.position_of_loc after r_stop')
  in
  let processed = List.map shift_range st.overview.processed in
  let processing = List.map shift_range st.overview.processing in
  let prepared = List.map shift_range st.overview.prepared in
  let overview = {processed; processing; prepared} in
  {st with overview}

let shift_diagnostics_locs st ~start ~offset =
  (* Simplified stub for EasyCrypt - diagnostic location shifting not implemented *)
  log (fun () -> Printf.sprintf "EasyCrypt stub: shift_diagnostics_locs start=%d offset=%d" start offset);
  st (* Return unchanged state *)

let executed_ids st =
  SM.fold (fun id (p,_) acc ->
    match p with
    | Done _ -> id :: acc
    | _ -> acc) st.of_sentence []

let invalidate1 of_sentence id =
  try
    let p,_ = SM.find id of_sentence in
    match p with
    | Delegated (job_id,_) ->
        DelegationManager.cancel_job job_id;
        SM.remove id of_sentence
    | _ -> SM.remove id of_sentence
  with Not_found -> of_sentence

let cancel1 todo invalid_id =
  let task_of_id = function
    | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } -> Int.equal id invalid_id
    | PDelegate _ -> false
  in
  List.filter task_of_id todo

let rec invalidate document schedule id st =
  log (fun () -> "Invalidating: " ^ Document.sentence_ido_string id);
  let of_sentence = invalidate1 st.of_sentence id in
  let todo = cancel1 st.todo id in
  let old_jobs = Queue.copy jobs in
  let removed = ref [] in
  Queue.clear jobs;
  Queue.iter (fun ((_, cancellation, { ProofJob.terminator_id; tasks }) as job) ->
    if terminator_id != id then
      Queue.push job jobs
    else begin
      Sel.Event.cancel cancellation;
      removed := List.map (fun e -> PExec e) tasks :: !removed
    end) old_jobs;
  let of_sentence = List.fold_left invalidate1 of_sentence
    List.(concat (map (fun tasks -> map id_of_prepared_task tasks) !removed)) in
  if of_sentence == st.of_sentence then st else
  let deps = Scheduler.dependents schedule id in
  SentenceIdSet.fold (invalidate document schedule) deps { st with of_sentence; todo }

(* Coq-specific context management commented out for EasyCrypt *)
let context_of_state st =
  log (fun () -> "EasyCrypt stub: context_of_state");
  (* Return dummy context - TODO: implement EasyCrypt context if needed *)
  ()

let get_context st id =
  log (fun () -> Printf.sprintf "🔍 EasyCrypt: get_context for id %d" id);
  Printf.eprintf "DEBUG: ExecutionManager.get_context called for sentence %d\n%!" id;
  Printf.eprintf "DEBUG: Available executed scopes: [%s]\n%!" 
    (String.concat "; " (List.map string_of_int (SM.fold (fun k _ acc -> k :: acc) st.executed_scopes [])));
  try
    let scope = SM.find id st.executed_scopes in
    Printf.eprintf "✅ EasyCrypt: Found executed scope for sentence %d\n%!" id;
    Some scope
  with
  | Not_found -> 
    Printf.eprintf "❌ EasyCrypt: No executed scope found for sentence %d (not executed yet?)\n%!" id;
    None

let get_initial_context st =
  log (fun () -> "EasyCrypt: get_initial_context");
  (* Initialize EasyCrypt if not already done *)
  if not !easycrypt_initialized then (
    log (fun () -> "Initializing EasyCrypt commands system...");
    try
      (* Initialize EasyCrypt with basic configuration *)
      let checkmode = {
        EcLib.EcCommands.cm_checkall  = false;
        EcLib.EcCommands.cm_timeout   = 3;
        EcLib.EcCommands.cm_cpufactor = 1;
        EcLib.EcCommands.cm_nprovers  = 4;
        EcLib.EcCommands.cm_provers   = None;
        EcLib.EcCommands.cm_profile   = false;
        EcLib.EcCommands.cm_iterate   = false;
      } in
      EcLib.EcCommands.initialize ~restart:false ~undo:true ~boot:false ~checkmode;
      easycrypt_initialized := true;
      log (fun () -> "EasyCrypt commands system initialized successfully");
    with
    | exn -> 
      log (fun () -> Printf.sprintf "Failed to initialize EasyCrypt: %s" (Printexc.to_string exn));
  );
  st.initial (* Return the initial EasyCrypt scope *)

let set_hybrid_proof st id proof_json =
  { st with hybrid_proofs = SM.add id proof_json st.hybrid_proofs }

let hybrid_proof_for_sentence st id =
  try Some (SM.find id st.hybrid_proofs) with Not_found -> None

let get_vernac_state st id =
  match find_fulfilled_opt id st.of_sentence with
  | None -> log (fun () -> "Cannot find state for get_context"); None
  | Some (Error (_, None)) -> log (fun () -> "State requested after error with no state"); None
  | Some (Success None) -> log (fun () -> "State requested in a remotely checked state"); None
  | Some (Success (Some st))
  | Some (Error (_, Some st)) ->
    Some st

let get_easycrypt_state st id =
  log (fun () -> Printf.sprintf "get_easycrypt_state for id %d" id);
  match find_fulfilled_opt id st.of_sentence with
  | None -> None
  | Some (Error (_, None)) -> None
  | Some (Success None) -> None
  | Some (Success (Some scope))
  | Some (Error (_, Some scope)) -> Some scope

module ProofWorkerProcess = struct
  type options = ProofWorker.options
  let parse_options = ProofWorker.parse_options
  let main ~st:_ options =
    let send_back, job = ProofWorker.setup_plumbing options in
    worker_main job ~send_back
  let log = ProofWorker.log
end

