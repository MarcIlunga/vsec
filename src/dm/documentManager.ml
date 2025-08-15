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

(* [%%import "vsrocq_config.mlh"] - commented out for EasyCrypt *)

open Lsp.Types
open Protocol
open Protocol.LspWrapper
open Protocol.ExtProtocol
(* open Protocol.Printing - commented out for EasyCrypt *)
open Types

let Log log = Log.mk_log "documentManager"

type observe_id = Id of Types.sentence_id | Top

type blocking_error = {
  last_range: Range.t;
  error_range: Range.t
}

let to_sentence_id = function
| Top -> None
| Id id -> Some id

type document_state =
| Parsing
| Parsed
(* | Executing of sentence_id TODO: ADD EXEDCUTING STATE
| Executed of sentence_id *)

type state = {
  uri : DocumentUri.t;
  init_vs : EcLib.EcScope.scope;
  opts : string list; (* simplified from Coqargs.injection_command for EasyCrypt *)
  document : Document.document;
  execution_state : ExecutionManager.state;
  observe_id : observe_id;
  cancel_handle : Sel.Event.cancellation_handle option;
  document_state: document_state;
}

type event =
  | Execute of { (* we split the computation to help interruptibility *)
      id : Types.sentence_id; (* sentence of interest *)
      vst_for_next_todo : EcLib.EcScope.scope; (* the state to be used for the next
        todo, it is not necessarily the state of the last sentence, since it
        may have failed and this is a surrogate used for error resiliancy *)
      task : ExecutionManager.prepared_task;
      started : float; (* time *)
    }
  | ExecutionManagerEvent of ExecutionManager.event
  | ParseBegin
  | Observe of Types.sentence_id
  | SendProofView of (Types.sentence_id option)
  | DocumentEvent of Document.event
  | SendBlockOnError of Types.sentence_id
  | SendMoveCursor of Range.t
  | SendHighlight of Range.t
  | ClearHighlight
  | JumpToRange of Range.t

type handled_event = {
    state : state option;
    events: event Sel.Event.t list;
    update_view: bool;
    notification: string option; (* simplified from Notification.Server.t for EasyCrypt *)
}

let pp_event fmt = function
  | Execute { id; started; _ } ->
      let time = Unix.gettimeofday () -. started in 
      Stdlib.Format.fprintf fmt "ExecuteToLoc %d (started %2.3f ago)" id time
  | ExecutionManagerEvent _ -> Stdlib.Format.fprintf fmt "ExecutionManagerEvent"
  | ParseBegin ->
    Stdlib.Format.fprintf fmt "ParseBegin"
  | Observe id ->
    Stdlib.Format.fprintf fmt "Observe %d" id
  | SendProofView id_opt ->
    Stdlib.Format.fprintf fmt "SendProofView %s" @@ (match id_opt with Some id -> string_of_int id | None -> "None")
  | DocumentEvent event -> Stdlib.Format.fprintf fmt "DocumentEvent event: "; Document.pp_event fmt event
  | SendBlockOnError id ->
    Stdlib.Format.fprintf fmt "SendBlockOnError %d" id
  | SendMoveCursor range ->
    Stdlib.Format.fprintf fmt "SendBlockOnError %s" @@ (Range.to_string range)
  | SendHighlight range ->
    Stdlib.Format.fprintf fmt "SendHighlight %s" @@ (Range.to_string range)
  | ClearHighlight ->
    Stdlib.Format.fprintf fmt "ClearHighlight"
  | JumpToRange range ->
    Stdlib.Format.fprintf fmt "JumpToRange %s" @@ (Range.to_string range)

let inject_em_event x = Sel.Event.map (fun e -> ExecutionManagerEvent e) x
let inject_em_events events = List.map inject_em_event events
let inject_doc_event x = Sel.Event.map (fun e -> DocumentEvent e) x
let inject_doc_events events = List.map inject_doc_event events
let mk_proof_view_event id =
  Sel.now ~priority:PriorityManager.proof_view (SendProofView (Some id))
let mk_proof_view_event_empty =
  Sel.now ~priority:PriorityManager.proof_view (SendProofView None)
let mk_observe_event id =
  Sel.now ~priority:PriorityManager.execution (Observe id)
let mk_move_cursor_event id = 
  let priority = PriorityManager.move_cursor in
  Sel.now ~priority @@ SendMoveCursor id

let mk_block_on_error_event last_range error_id background =
  let update_goal_view = [mk_proof_view_event error_id] in
  if background then
    update_goal_view
  else
    let red_flash =
      [Sel.now ~priority:PriorityManager.move_cursor @@ SendBlockOnError error_id] in
    let move_cursor =
      match last_range with
      | Some last_range -> [mk_move_cursor_event last_range]
      | None -> [] in
    red_flash @ move_cursor @ update_goal_view
  
type events = event Sel.Event.t list

let executed_ranges st =
  (* EasyCrypt stub - Settings mode not implemented yet *)
  ExecutionManager.overview st.execution_state

let observe_id_range st = 
  let doc = Document.raw_document st.document in
  match st.observe_id with
    | Top -> None
    | Id id -> match Document.get_sentence st.document id with
      | None -> failwith "observe_id does not exist"
      | Some { start; stop } ->
      let start = RawDocument.position_of_loc doc start in 
      let end_ = RawDocument.position_of_loc doc stop in 
      let range = Range.{ start; end_ } in 
      Some range

let is_parsing st =  st.document_state = Parsing

(* Simplified version compatibility check *)
let message_of_string x = x
(* End of compatibility check *)

(* 🎯 Phase 8.1.3: EasyCrypt Location Conversion *)
let convert_ec_location_to_range doc (loc : EasyCryptLocation.t) =
  let start_pos = Position.create 
    ~line:loc.start_line ~character:loc.start_col in
  let end_pos = Position.create 
    ~line:loc.end_line ~character:loc.end_col in
  Range.create ~start:start_pos ~end_:end_pos

let convert_ec_location_opt doc = function
  | None -> None
  | Some loc -> Some (convert_ec_location_to_range doc loc)

let make_diagnostic doc range oloc message severity code =
  let range =
    match oloc with
    | None -> range
    | Some loc ->
      RawDocument.range_of_loc (Document.raw_document doc) loc
  in
  let code, data =
    match code with
    | None -> None, None
    | Some (x,z) -> Some x, Some z in
  Diagnostic.create ?code ?data ~range ~message:(message_of_string message) ~severity ()

let mk_diag st (id,(lvl,oloc,qf,msg)) =
  let code = 
    (* EasyCrypt doesn't use Coq's Quickfix system *)
    match qf with
    | [] -> None
    | _qf -> None (* Simplified for EasyCrypt - no quickfix support *)
    in
    let lvl = DiagnosticSeverity.of_feedback_level lvl in
    make_diagnostic st.document (Document.range_of_id st.document id) oloc (`String msg) (DiagnosticSeverity.to_lsp lvl) code

let mk_error_diag st (id,(oloc,msg,qf)) = (* mk_diag st (id,(Feedback.Error,oloc, msg)) *)
  let code = 
    (* EasyCrypt doesn't use Coq's Quickfix system *)
    match qf with
    | None -> None
    | Some _qf -> None (* Simplified for EasyCrypt - no quickfix support *)
  in
  let severity = DiagnosticSeverity.Error in
  make_diagnostic st.document (Document.range_of_id st.document id) oloc (`String msg) (DiagnosticSeverity.to_lsp severity) code


let mk_parsing_error_diag st Document.{ msg = (oloc,msg); start; stop; str } =
  let doc = Document.raw_document st.document in
  let severity = DiagnosticSeverity.Error in
  let start = RawDocument.position_of_loc doc start in
  let end_ = RawDocument.position_of_loc doc stop in
  let range = Range.{ start; end_ } in
  let code = None in (* EasyCrypt doesn't use quickfix *)
  make_diagnostic st.document range None (`String msg) (DiagnosticSeverity.to_lsp severity) code

let all_diagnostics st =
  let parse_errors = Document.parse_errors st.document in
  let all_exec_errors = ExecutionManager.all_errors st.execution_state in
  let all_feedback = ExecutionManager.all_feedback st.execution_state in
  (* we are resilient to a state where invalidate was not called yet *)
  let exists (id,_) = Option.is_some (Document.get_sentence st.document id) in
  let not_info (_, (lvl, _, _)) = 
    (* EasyCrypt simplified - no Feedback levels, treat all as non-info *)
    true
  in
  let exec_errors = all_exec_errors |> List.filter exists in
  let feedback = all_feedback |> List.filter (fun (id, _) -> Option.is_some (Document.get_sentence st.document id)) |> List.filter not_info in
  List.map (mk_parsing_error_diag st) parse_errors @
    (* 🎯 Phase 8.1.3: Enhanced Diagnostics - RESTORED! *)
    List.map (mk_error_diag st) exec_errors @
    List.map (fun (id, (lvl, oloc, msg)) -> mk_diag st (id, (lvl, oloc, [], msg))) feedback

(* ================= Diagnostics publication (LSP) ================= *)
let diagnostics_to_json st =
  let doc = Document.raw_document st.document in
  let to_range_json start_loc stop_loc =
    let s = RawDocument.position_of_loc doc start_loc in
    let e = RawDocument.position_of_loc doc stop_loc in
    `Assoc [
      ("start", `Assoc [ ("line", `Int s.line); ("character", `Int s.character) ]);
      ("end", `Assoc [ ("line", `Int e.line); ("character", `Int e.character) ])
    ]
  in
  let parse_errors = Document.parse_errors st.document in
  let diags = List.map (fun Document.{ start; stop; msg = (_loc,msg); _ } ->
    `Assoc [
      ("range", to_range_json start stop);
      ("severity", `Int 1); (* Error *)
      ("message", `String msg)
    ]) parse_errors in
  diags

let build_publish_diagnostics_notification st =
  let uri = st.uri |> DocumentUri.to_string in
  let diagnostics = diagnostics_to_json st in
  `Assoc [
    ("jsonrpc", `String "2.0");
    ("method", `String "textDocument/publishDiagnostics");
    ("params", `Assoc [
      ("uri", `String uri);
      ("diagnostics", `List diagnostics)
    ])
  ]

let id_of_pos st pos =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  match Document.find_sentence_before st.document loc with
  | None -> None
  | Some { id } -> Some id

let id_of_sentence_after_pos st pos =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  (* if the current loc falls squarely within a sentence *)
  match Document.find_sentence st.document loc with
  | Some { id } -> Some id
  | None -> 
    (** otherwise the sentence start is after the loc,
        so we must be in the whitespace before the sentence
        and need to interpret to the sentence before instead
    *)
    match Document.find_sentence_before st.document loc with
    | None -> None
    | Some { id } -> Some id

let id_of_pos_opt st = function
  | None -> begin match st.observe_id with  Top -> None | Id id -> Some id end
  | Some pos -> id_of_pos st pos

let get_messages st id =
  let error = ExecutionManager.error st.execution_state id in
  let feedback = ExecutionManager.feedback st.execution_state id in
  let feedback = List.map (fun (lvl,_oloc,msg) -> DiagnosticSeverity.to_lsp (DiagnosticSeverity.of_feedback_level lvl), msg) feedback  in
  match error with
  | Some (_oloc,msg) -> (DiagnosticSeverity.to_lsp DiagnosticSeverity.Error, msg) :: feedback
  | None -> feedback

let get_string_messages st id =
  let error = ExecutionManager.error st.execution_state id in
  let feedback = ExecutionManager.feedback st.execution_state id in
  let feedback = List.map (fun (lvl,_oloc,msg) -> DiagnosticSeverity.of_feedback_level lvl, msg) feedback  in
  match error with
  | Some (_oloc,msg) -> (DiagnosticSeverity.Error, msg) :: feedback
  | None -> feedback

let get_info_messages st pos =
  match id_of_pos_opt st pos with
  | None -> log (fun () -> "get_messages: Could not find id");[]
  | Some id -> log (fun () -> "get_messages: Found id");
    let info (lvl, _, _) = 
      (* EasyCrypt simplified - treat all as info for now *)
      true
    in
    let feedback = ExecutionManager.feedback st.execution_state id in
    let feedback = feedback |> List.filter info in
    List.map (fun (lvl,_oloc,msg) -> DiagnosticSeverity.to_lsp (DiagnosticSeverity.of_feedback_level lvl), msg) feedback

let create_execution_event background event =
  let priority = if background then None else Some PriorityManager.execution in
  Sel.now ?priority event

let state_before_error state error_id loc =
  match Document.get_sentence state.document error_id with
  | None -> state, None
  | Some { start } ->
    let errored_sentence_range = Document.range_of_id_with_blank_space state.document error_id in
    let error_range = 
      Option.fold ~none:errored_sentence_range ~some:(fun loc -> RawDocument.range_of_loc (Document.raw_document state.document) loc) loc in
    match Document.find_sentence_before state.document start with
    | None ->
      let observe_id = Top in
      {state with observe_id}, Some error_range
    | Some { id } ->
      let observe_id = (Id id) in
      {state with observe_id}, Some error_range

(* Hybrid fallback: if no task executes, try sending the raw sentence to easycrypt -emacs
   and store a minimal proofView so the UI reflects goals. *)
let run_hybrid_for_sentence st id =
  match Document.get_sentence st.document id with
  | None -> st, false
  | Some s ->
    let text = Document.Internal.string_of_sentence s in
    let goals = ExecutionManager.execute_with_goal_extraction text in
    match goals with
    | [] -> st, false
    | goals ->
      let uri_str = Lsp.Types.DocumentUri.to_string st.uri in
      let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
      let goals_json =
        `List (List.mapi (fun idx (g:ExecutionManager.hybrid_goal) ->
          `Assoc [ ("id", `Int (idx + 1)); ("hypotheses", `List (List.map (fun h -> `String h) g.hyps)); ("goal", `String g.goal) ]) goals)
      in
      let output = ExecutionManager.get_last_easycrypt_raw_output () in
      let progress = Pg_compat.progress_of_output output in
      let remaining = if Pg_compat.contains_no_more_goals output then 0 else (match Pg_compat.extract_remaining_count output with Some n -> n | None -> -1) in
      let proof_json : Yojson.Safe.t = `Assoc [
        ("goals", goals_json);
        ("shelvedGoals", `List []);
        ("givenUpGoals", `List []);
        ("unfocusedGoals", `List []);
        ("navigation", `Null);
        ("current_lemma", `Null);
        ("proof_progress", `Float progress);
        ("remaining", `Int remaining)
      ] in
      let notif_json : Yojson.Safe.t = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "prover/proofView");
        ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json) ])
      ] in
      let exec_state' = ExecutionManager.set_hybrid_proof st.execution_state id notif_json in
      { st with execution_state = exec_state' }, true

(* Hybrid replay: feed all sentences up to [id] to easycrypt -emacs and store a full proofView JSON *)
let hybrid_replay_up_to_sentence st id =
  let sentences = Document.Internal.sentences_in_order st.document in
  (* Helpers *)
  let is_kw_line kw (s: Document.sentence) =
    match s.ast with
    | Error _ -> false
    | Parsed p ->
      let t = String.lowercase_ascii (String.trim p.ast) in
      let t = if String.length t > 0 && t.[String.length t - 1] = '.' then String.sub t 0 (String.length t - 1) else t in
      t = kw
  in
  let is_proof_start s = is_kw_line "proof" s in
  let is_qed s = is_kw_line "qed" s in
  let is_lemma_like (s: Document.sentence) =
    match s.ast with
    | Error _ -> false
    | Parsed p ->
      (* Prefer classification when available *)
      (match p.classification with
       | EasyCryptClassification.EcDefinition -> true
       | _ ->
         let t = String.lowercase_ascii (String.trim p.ast) in
         (* consider multiple declaration starters *)
         let starts_with w =
           let lw = String.length w in
           String.length t >= lw && String.sub t 0 lw = w
         in
         starts_with "lemma " || starts_with "theorem " || starts_with "axiom " || starts_with "proc " || starts_with "module " || starts_with "theory ")
  in
  (* Find indices *)
  let target_idx =
    let rec find_i i = function
      | [] -> None
      | s :: rest -> if s.Document.id = id then Some i else find_i (i+1) rest
    in find_i 0 sentences
  in
  (* For multi-proof correctness, feed from the beginning of the file to include all context. *)
  let start_idx = 0 in
  let end_idx =
    match target_idx with
    | None -> -1
    | Some ti ->
      (* Clamp the end to the first qed. after start_idx, if any, to stay within current proof block *)
      let rec find_qed k =
        if k > ti then None else
        let s = List.nth sentences k in
        if is_qed s then Some k else find_qed (k+1)
      in
      (match find_qed start_idx with
       | None -> ti
       | Some q -> min q ti)
  in
  (* Feed sentences from start_idx up to end_idx inclusive *)
  let () = Printf.eprintf "🔁 Hybrid replay (full): resetting EasyCrypt process and feeding sentences (start_idx=%d end_idx=%d target id=%d)\n%!" start_idx end_idx id in
  (* Reset EasyCrypt process to ensure deterministic replay state *)
  let () = ExecutionManager.kill_easycrypt_process () in
  (* Ensure a fresh EasyCrypt process and reader thread for the replay, so we capture clean output *)
  let _ = ExecutionManager.spawn_easycrypt_process () in
  let rec feed fed_any i =
    if i < 0 || i >= List.length sentences then fed_any else
    let s = List.nth sentences i in
    if i > end_idx then fed_any else (
      let text = Document.Internal.string_of_sentence s in
      ignore (ExecutionManager.execute_with_goal_extraction text);
      feed true (i+1)
    )
  in
  let fed = match target_idx with None -> false | Some _ -> feed false start_idx in
  if not fed then st, false else (
    let output = ExecutionManager.get_last_easycrypt_raw_output () in
    let groups = Pg_compat.parse_goal_groups_from_output output in
    match groups.Pg_compat.current, groups.shelved, groups.given_up, groups.unfocused with
    | ([], [], [], []) -> st, false
    | _ ->
      let uri_str = Lsp.Types.DocumentUri.to_string st.uri in
      let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
      let to_goals_json xs =
        `List (List.mapi (fun idx (hyps, goal) ->
          `Assoc [ ("id", `Int (idx + 1)); ("hypotheses", `List (List.map (fun h -> `String h) hyps)); ("goal", `String goal) ]) xs)
      in
      let goals_json = to_goals_json groups.current in
      let shelved_json = to_goals_json groups.shelved in
      let given_up_json = to_goals_json groups.given_up in
      let unfocused_json = to_goals_json groups.unfocused in
      let progress = Pg_compat.progress_of_output output in
      let remaining = if Pg_compat.contains_no_more_goals output then 0 else (match Pg_compat.extract_remaining_count output with Some n -> n | None -> -1) in
      let proof_json : Yojson.Safe.t = `Assoc [
        ("goals", goals_json);
        ("shelvedGoals", shelved_json);
        ("givenUpGoals", given_up_json);
        ("unfocusedGoals", unfocused_json);
        ("navigation", `Null);
        ("current_lemma", `Null);
        ("proof_progress", `Float progress);
        ("remaining", `Int remaining)
      ] in
      let notif_json : Yojson.Safe.t = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "prover/proofView");
        ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json); ("messages", `List []) ])
      ] in
      let exec_state' = ExecutionManager.set_hybrid_proof st.execution_state id notif_json in
      { st with execution_state = exec_state' }, true
  )

let observe ~background state id ~should_block_on_error : (state * event Sel.Event.t list) =
  Printf.eprintf "DEBUG: observe function called with id: %s\n%!" (Document.sentence_ido_string id);
  match Document.get_sentence state.document id with
  | None -> 
    Printf.eprintf "DEBUG: observe - No sentence found for id: %s\n%!" (Document.sentence_ido_string id);
    state, [] (* TODO error? *)
  | Some { id } ->
    Printf.eprintf "DEBUG: observe - Found sentence for id: %s, proceeding...\n%!" (Document.sentence_ido_string id);
    Option.iter Sel.Event.cancel state.cancel_handle;
    let vst_for_next_todo, execution_state, task, error_id = ExecutionManager.build_tasks_for state.document (Document.schedule state.document) state.execution_state id should_block_on_error in
    Printf.eprintf "DEBUG: observe - ExecutionManager.build_tasks_for returned task: %s, error_id: %s\n%!" 
      (match task with Some _ -> "Some" | None -> "None")
      (match error_id with Some (eid, _) -> Document.sentence_ido_string eid | None -> "None");
    match task with
    | Some task -> (* task will only be Some if there is no error *)
        let event = create_execution_event background (Execute {id; vst_for_next_todo; task; started = Unix.gettimeofday ()}) in
        let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
        Printf.eprintf "DEBUG: observe - Setting observe_id to %s\n%!" (Document.sentence_ido_string id);
        {state with execution_state; cancel_handle; observe_id = Id id}, [event]
    | None ->
      begin match error_id with
      | None ->
        (* No planned task: run hybrid replay up to this sentence to provide goals immediately *)
        let state', ran = hybrid_replay_up_to_sentence state id in
        if ran then (
          Printf.eprintf "DEBUG: observe - No task, hybrid executed for id %s\n%!" (Document.sentence_ido_string id);
          {state' with observe_id = Id id}, []
        ) else (
          Printf.eprintf "DEBUG: observe - No task, setting observe_id to %s\n%!" (Document.sentence_ido_string id);
          {state with execution_state; observe_id = Id id}, []
        )
      | Some (error_id, loc) ->
        let state, error_range = state_before_error state error_id loc in
        let events = mk_block_on_error_event error_range error_id background in
        Printf.eprintf "DEBUG: observe - Error case, setting observe_id to %s\n%!" (Document.sentence_ido_string id);
        {state with execution_state; observe_id = Id id}, events
      end

let run_hybrid_for_sentence st id =
  match Document.get_sentence st.document id with
  | None -> st, false
  | Some s ->
    let text = Document.Internal.string_of_sentence s in
    let goals = ExecutionManager.execute_with_goal_extraction text in
    match goals with
    | [] -> st, false
    | goals ->
      let uri_str = Lsp.Types.DocumentUri.to_string st.uri in
      let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
      let goals_json =
        `List (List.mapi (fun idx (g:ExecutionManager.hybrid_goal) ->
          `Assoc [
            ("id", `Int (idx + 1));
            ("hypotheses", `List (List.map (fun h -> `String h) g.hyps));
            ("goal", `String g.goal)
          ]) goals)
      in
      let proof_json : Yojson.Safe.t = `Assoc [
        ("goals", goals_json);
        ("shelvedGoals", `List []);
        ("givenUpGoals", `List []);
        ("unfocusedGoals", `List []);
        ("navigation", `Null);
        ("current_lemma", `Null);
        ("proof_progress", `Float 0.0)
      ] in
      let notif_json : Yojson.Safe.t = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "prover/proofView");
        ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json) ])
      ] in
      let exec_state' = ExecutionManager.set_hybrid_proof st.execution_state id notif_json in
      { st with execution_state = exec_state' }, true

let reset_to_top st = { st with observe_id = Top }


let get_document_proofs st =
  (* EasyCrypt stub - proof block analysis not implemented yet *)
  []

let to_document_symbol elem =
  let Document.{name; statement; range; type_} = elem in
  let kind = begin match type_ with
  | TheoremKind -> SymbolKind.Function
  | DefinitionType -> SymbolKind.Variable
  | InductiveType -> SymbolKind.Struct
  | Other -> SymbolKind.Null
  | BeginSection | BeginModule -> SymbolKind.Class
  | End -> SymbolKind.Null
  end in
  DocumentSymbol.{name; detail=(Some statement); kind; range; selectionRange=range; children=None; deprecated=None; tags=None;}

let rec get_document_symbols outline (sec_or_m: DocumentSymbol.t list) symbols =
  let add_child (s_father: DocumentSymbol.t) s_child =
    let children = match s_father.children with
      | None -> Some [s_child]
      | Some l -> Some (l @ [s_child])
    in
    {s_father with children} 
  in
  let record_in_outline outline symbol sec_or_m =
    match sec_or_m with
    | [] ->
      let symbols = symbols @ [symbol] in
      get_document_symbols outline sec_or_m symbols
    | s :: l ->
      let s = add_child s symbol in
      get_document_symbols outline (s::l) symbols
  in
  match outline with
  | [] -> symbols
  | e :: l ->
    let Document.{type_} = e in
    match type_ with
    | TheoremKind | DefinitionType | InductiveType  | Other ->
      let symbol = to_document_symbol e in
      record_in_outline l symbol sec_or_m
    | BeginSection ->
      let symbol = to_document_symbol e in
      get_document_symbols l (symbol :: sec_or_m) symbols
    | BeginModule ->
      let symbol = to_document_symbol e in
      get_document_symbols l (symbol :: sec_or_m) symbols
    | End ->
      match sec_or_m with
      | [] -> log(fun () -> "Trying to end a module or section with no begin"); get_document_symbols l [] symbols
      | symbol :: s_l ->
        match s_l with
        | [] ->
          get_document_symbols l s_l (symbols @ [symbol])
        | s_parent :: s_l ->
          let s = add_child s_parent symbol in
          get_document_symbols l (s :: s_l) symbols
          

let get_document_symbols st =
  let outline = List.rev @@ Document.outline st.document in
  get_document_symbols outline [] []

let interpret_to st id check_mode =
  Printf.eprintf "🎯 DocumentManager: interpret_to called for sentence %s\n%!" (Document.sentence_ido_string id);
  (* For now, just observe the target sentence directly *)
  observe ~background:false st id ~should_block_on_error:false

let interpret_to_next_position st pos =
  Printf.eprintf "🎯 DocumentManager: interpret_to_next_position called for position %d:%d\n%!" pos.Lsp.Types.Position.line pos.Lsp.Types.Position.character;
  let target_loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  match Document.find_sentence_before st.document target_loc with
  | None -> st, []
  | Some s_at_pos ->
    (match Document.find_sentence_after st.document (s_at_pos.stop + 1) with
     | None -> st, []
     | Some next_s -> observe ~background:false st next_s.id ~should_block_on_error:false)

(* Hybrid fallback: if no task executes, try sending the raw sentence to easycrypt -emacs
   and store a minimal proofView so the UI reflects goals. *)
let run_hybrid_for_sentence st id =
  match Document.get_sentence st.document id with
  | None -> st, false
  | Some s ->
    let text = Document.Internal.string_of_sentence s in
    let goals = ExecutionManager.execute_with_goal_extraction text in
    match goals with
    | [] -> st, false
    | goals ->
      let uri_str = Lsp.Types.DocumentUri.to_string st.uri in
      let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
      let goals_json =
        `List (List.mapi (fun idx (g:ExecutionManager.hybrid_goal) ->
          `Assoc [
            ("id", `Int (idx + 1));
            ("hypotheses", `List (List.map (fun h -> `String h) g.hyps));
            ("goal", `String g.goal)
          ]) goals)
      in
      let proof_json : Yojson.Safe.t = `Assoc [
        ("goals", goals_json);
        ("shelvedGoals", `List []);
        ("givenUpGoals", `List []);
        ("unfocusedGoals", `List []);
        ("navigation", `Null);
        ("current_lemma", `Null);
        ("proof_progress", `Float 0.0)
      ] in
      let notif_json : Yojson.Safe.t = `Assoc [
        ("jsonrpc", `String "2.0");
        ("method", `String "prover/proofView");
        ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json) ])
      ] in
      let exec_state' = ExecutionManager.set_hybrid_proof st.execution_state id notif_json in
      { st with execution_state = exec_state' }, true

let interpret_to_position st pos =
  Printf.eprintf "🎯 DocumentManager: interpret_to_position called for position %d:%d\n%!" pos.Lsp.Types.Position.line pos.Lsp.Types.Position.character;
  
  (* Convert position to document location *)
  let target_loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  Printf.eprintf "📍 DocumentManager: Target location: %d\n%!" target_loc;
  
  (* Find the sentence that contains or comes before this position *)
  let target_sentence_opt = Document.find_sentence_before st.document target_loc in
  
  match target_sentence_opt with
  | None -> 
    Printf.eprintf "❌ DocumentManager: No sentences found before target position\n%!";
    st, []
  | Some target_sentence ->
    Printf.eprintf "🎯 DocumentManager: Target sentence found - id: %s, observing directly\n%!" 
      (Document.sentence_ido_string target_sentence.id);
    (* For now, just observe the target sentence directly *)
    observe ~background:false st target_sentence.id ~should_block_on_error:false

let get_next_range st pos =
  match id_of_pos st pos with
  | None -> None
  | Some id ->
    match Document.get_sentence st.document id with
    | None -> None
    | Some { stop } ->
      match Document.find_sentence_after st.document (stop+1) with
      | None -> Some (Document.range_of_id st.document id)
      | Some { id } -> Some (Document.range_of_id st.document id)

let get_previous_range st pos =
  match id_of_pos st pos with
  | None -> None
  | Some id ->
    match Document.get_sentence st.document id with
    | None -> None
    | Some { start } ->
      match Document.find_sentence_before st.document (start) with
      | None -> Some (Document.range_of_id st.document id)
      | Some { id } -> Some (Document.range_of_id st.document id)

let interpret_to_previous st =
  Printf.eprintf "🎯 DocumentManager: interpret_to_previous called\n%!";
  (* Move to the previous sentence *)
  match st.observe_id with
  | Top -> 
    Printf.eprintf "📍 DocumentManager: Already at top, cannot go previous\n%!";
    st, []
  | Id current_id ->
    Printf.eprintf "📍 DocumentManager: Current observe_id: %s, finding previous sentence\n%!" (Document.sentence_ido_string current_id);
    (match Document.get_sentence st.document current_id with
      | None -> 
       Printf.eprintf "❌ DocumentManager: Current sentence not found\n%!";
       st, []
     | Some current_sentence ->
       (* Find sentence before the current sentence's start position *)
       (match Document.find_sentence_before st.document (current_sentence.start - 1) with
        | None -> 
          Printf.eprintf "🏁 DocumentManager: No previous sentence found, going to top\n%!";
          {st with observe_id = Top}, []
        | Some prev_sentence ->
          Printf.eprintf "✅ DocumentManager: Found previous sentence, setting observe_id to: %s\n%!" (Document.sentence_ido_string prev_sentence.id);
          let range = Document.range_of_id st.document prev_sentence.id in
          let st' = {st with observe_id = Id prev_sentence.id} in
          let st'', evs = observe ~background:false st' prev_sentence.id ~should_block_on_error:false in
          let highlight_evt = Sel.now ~priority:PriorityManager.move_cursor (SendHighlight range) in
          st'', [Sel.now ~priority:PriorityManager.move_cursor ClearHighlight; mk_move_cursor_event range; highlight_evt] @ evs))

let revert_to_previous_and_execute st =
  Printf.eprintf "🔄 DocumentManager: revert_to_previous_and_execute called\n%!";
  match st.observe_id with
  | Top -> st, []
  | Id current_id ->
    (match Document.get_sentence st.document current_id with
      | None -> st, []
     | Some current_sentence ->
       (match Document.find_sentence_before st.document (current_sentence.start - 1) with
        | None -> {st with observe_id = Top}, []
        | Some prev_sentence ->
          let range = Document.range_of_id st.document prev_sentence.id in
          let st' = {st with observe_id = Id prev_sentence.id} in
          let st'', events = observe ~background:false st' prev_sentence.id ~should_block_on_error:false in
          let proof_evt = mk_proof_view_event prev_sentence.id in
          st'', [Sel.now ~priority:PriorityManager.move_cursor ClearHighlight; mk_move_cursor_event range; proof_evt] @ events))

let jump_to_next_error st =
  let errors = ExecutionManager.all_errors st.execution_state in
  let with_ranges =
    List.filter_map (fun (id, _e) -> match Document.get_sentence st.document id with None -> None | Some _ -> Some (id, Document.range_of_id st.document id)) errors in
  let start_pos_opt = match observe_id_range st with None -> None | Some r -> Some r.start in
  let sorted = List.sort (fun (_i1, r1) (_i2, r2) -> Position.compare r1.Range.start r2.Range.start) with_ranges in
  let next_range =
    match start_pos_opt with
    | None -> (match sorted with [] -> None | (_id, r) :: _ -> Some r)
    | Some spos ->
      let rec find = function
        | [] -> None
        | (_id, r) :: tl -> if Position.compare r.Range.start spos > 0 then Some r else find tl
      in (match find sorted with Some r -> Some r | None -> (match sorted with [] -> None | (_id, r) :: _ -> Some r))
  in
  match next_range with None -> st, [] | Some r -> st, [Sel.now ~priority:PriorityManager.move_cursor (JumpToRange r)]

let interpret_to_next st =
  Printf.eprintf "🚀 DocumentManager: interpret_to_next called\n%!";
  (* Get the current observe_id and try to move to next sentence *)
  match st.observe_id with
  | Top ->
    Printf.eprintf "📍 DocumentManager: No current observe_id, trying to start from beginning\n%!";
    (* Try to get the first sentence and execute it *)
    Printf.eprintf "DEBUG: interpret_to_next - Looking for first sentence...\n%!";
    (match Document.get_first_sentence st.document with
     | None -> 
       Printf.eprintf "❌ DocumentManager: No sentences found in document\n%!";
       st, []
     | Some sentence ->
       Printf.eprintf "✅ DocumentManager: Found first sentence, observing id: %s\n%!" (Document.sentence_ido_string sentence.id);
       let (new_st, events) = observe ~background:false st sentence.id ~should_block_on_error:false in
       Printf.eprintf "DEBUG: interpret_to_next - observe returned, new observe_id: %s\n%!" 
         (match new_st.observe_id with Top -> "Top" | Id id -> Document.sentence_ido_string id);
       (new_st, events))
  | Id current_id ->
    Printf.eprintf "📍 DocumentManager: Current observe_id: %s, finding next sentence\n%!" (Document.sentence_ido_string current_id);
    (* Try to get the next sentence after current position *)
    (match Document.get_sentence st.document current_id with
     | None -> 
       Printf.eprintf "❌ DocumentManager: Current sentence not found\n%!";
       st, []
     | Some current_sentence ->
       Printf.eprintf "🔍 DocumentManager: Current sentence details - id: %s, start: %d, stop: %d\n%!" 
         (Document.sentence_ido_string current_sentence.id) current_sentence.start current_sentence.stop;
       (* Find sentence after the current sentence's end position *)
       (match Document.find_sentence_after st.document (current_sentence.stop + 1) with
        | None -> 
          Printf.eprintf "🏁 DocumentManager: No next sentence found, at end of document\n%!";
          st, []
        | Some next_sentence ->
          Printf.eprintf "✅ DocumentManager: Found next sentence - id: %s, start: %d, stop: %d\n%!" 
            (Document.sentence_ido_string next_sentence.id) next_sentence.start next_sentence.stop;
          let (new_st, events) = observe ~background:false st next_sentence.id ~should_block_on_error:false in
          Printf.eprintf "DEBUG: interpret_to_next - observe returned, new observe_id: %s\n%!" 
            (match new_st.observe_id with Top -> "Top" | Id id -> Document.sentence_ido_string id);
          (new_st, events)))

let interpret_to_end st =
  Printf.eprintf "🎯 DocumentManager: interpret_to_end called\n%!";
  let rec loop acc_st acc_events current_id_opt =
    match current_id_opt with
    | None -> acc_st, acc_events
    | Some cid ->
      let st1, evs = observe ~background:false acc_st cid ~should_block_on_error:true in
      (* stop on error: SendBlockOnError will be queued in events in that case *)
      let has_error = false (* Simplified: block-on-error is handled by observe queueing appropriate UI events *) in
      if has_error then (st1, acc_events @ evs) else (
        match Document.get_sentence st1.document cid with
        | None -> st1, acc_events @ evs
        | Some s ->
          match Document.find_sentence_after st1.document (s.stop + 1) with
          | None -> st1, acc_events @ evs
          | Some ns -> loop st1 (acc_events @ evs) (Some ns.id))
  in
  let start_id_opt = match st.observe_id with Top -> (match Document.get_first_sentence st.document with None -> None | Some s -> Some s.id) | Id id -> Some id in
  loop st [] start_id_opt

let interpret_in_background st ~should_block_on_error =
  match Document.get_last_sentence st.document with
  | None -> (st, [])
  | Some {id} -> log (fun () -> "interpret_to_end id = " ^ Document.sentence_ido_string id); observe ~background:true st id ~should_block_on_error

let is_above st id1 id2 =
  let range1 = Document.range_of_id st id1 in
  let range2 = Document.range_of_id st id2 in
  Position.compare range1.start range2.start < 0

let validate_document state (Document.{unchanged_id; invalid_ids; previous_document; parsed_document}) =
  let state = {state with document=parsed_document} in
  let observe_id = match unchanged_id, state.observe_id with
    | None, Id _ -> Top
    | _, Top -> Top
    | Some id, Id id' -> if is_above previous_document id id' then (Id id) else state.observe_id
  in
  let execution_state =
    List.fold_left (fun st id ->
      ExecutionManager.invalidate previous_document (Document.schedule previous_document) id st
      ) state.execution_state (Types.SentenceIdSet.elements invalid_ids) in
  let execution_state = ExecutionManager.reset_overview execution_state previous_document in
  { state with  execution_state; observe_id; document_state = Parsed }

(* EasyCrypt stub - library initialization not implemented yet *)
let start_library _top _opts = ()

(* EasyCrypt stub - Coqargs not needed *)
let dirpath_of_top _top = []

let init init_vs uri ~text =
  (* EasyCrypt - initialize and immediately parse document *)
  Printf.eprintf "🎯 DocumentManager: init called for URI: %s\n%!" (DocumentUri.to_string uri);
  let document = Document.create_document init_vs text in
  Printf.eprintf "📄 DocumentManager: Document created, now parsing...\n%!";
  
  (* Parse document immediately instead of relying on events *)
  let parsed_doc, doc_events = Document.validate_document document in
  Printf.eprintf "✅ DocumentManager: Document parsed successfully during init\n%!";
  Printf.eprintf "🔍 DocumentManager: Created %d document parsing events\n%!" (List.length doc_events);
  
  let execution_state, feedback = ExecutionManager.init init_vs in
  let opts = [] in (* Default empty options for EasyCrypt *)
  let state = { uri; opts; init_vs; document = parsed_doc; execution_state; observe_id=Top; cancel_handle = None; document_state = Parsed } in
  
  Printf.eprintf "🚀 DocumentManager: Init complete, document ready for execution\n%!";
  state, [inject_em_event feedback] @ (inject_doc_events doc_events)

let reset { uri; opts; init_vs; document; execution_state; } =
  (* EasyCrypt stub - simplified reset *)
  let text = RawDocument.text @@ Document.raw_document document in
  let document = Document.create_document init_vs text in
  ExecutionManager.destroy execution_state;
  let execution_state, feedback = ExecutionManager.init init_vs in
  let observe_id = Top in
  let state = { uri; opts; init_vs; document; execution_state; observe_id; cancel_handle = None ; document_state = Parsing } in
  let priority = Some PriorityManager.launch_parsing in
  let event = Sel.now ?priority ParseBegin in
  state, [event] @ [inject_em_event feedback]

let apply_text_edits state edits =
  let apply_edit_and_shift_diagnostics_locs_and_overview state (range, new_text as edit) =
    let document = Document.apply_text_edit state.document edit in
    let exec_st = state.execution_state in
    let edit_start = RawDocument.loc_of_position (Document.raw_document state.document) range.Range.start in
    let edit_stop = RawDocument.loc_of_position (Document.raw_document state.document) range.Range.end_ in
    let edit_length = edit_stop - edit_start in
    let exec_st = ExecutionManager.shift_diagnostics_locs exec_st ~start:edit_stop ~offset:(String.length new_text - edit_length) in
    let execution_state = ExecutionManager.shift_overview exec_st ~before:(Document.raw_document state.document) ~after:(Document.raw_document document) ~start:edit_stop ~offset:(String.length new_text - edit_length) in
    {state with execution_state; document}
  in
  let state = List.fold_left apply_edit_and_shift_diagnostics_locs_and_overview state edits in
  let priority = Some PriorityManager.launch_parsing in
  let sel_event = Sel.now ?priority ParseBegin in
  (* H3.1: After edits, re-run hybrid for the currently observed sentence to refresh goals *)
  let state, extra_events =
    match state.observe_id with
    | Top -> state, []
    | Id sid ->
      let state', ran = hybrid_replay_up_to_sentence state sid in
      let events = if ran then [mk_proof_view_event sid] else [mk_proof_view_event sid] in
      state', events
  in
  state, [sel_event] @ extra_events

let execution_finished st id started =
  let time = Unix.gettimeofday () -. started in
  log (fun () -> Printf.sprintf "ExecuteToLoc %d ends after %2.3f" id time);
  (* We update the state to trigger a publication of diagnostics *)
  let update_view = true in
  let state = Some st in
  {state; events=[]; update_view; notification=None}

let execute st id vst_for_next_todo started task background block =
  let time = Unix.gettimeofday () -. started in
  let proof_view_event = (*When in continuous mode we always check if we should update the goal view *)
    if background then begin
      match st.observe_id with
      | Top -> []
      | Id o_id ->
        let s_id = ExecutionManager.get_id_of_executed_task task in
        if o_id = s_id then
          [mk_proof_view_event s_id]
        else []
    end
    else
      []
  in
  let move_cursor_and_highlight_for_task () =
    let s_id = ExecutionManager.get_id_of_executed_task task in
    let range = Document.range_of_id st.document s_id in
    let move_evt = mk_move_cursor_event range in
    let highlight_evt = Sel.now ~priority:PriorityManager.move_cursor (SendHighlight range) in
    [move_evt; highlight_evt]
  in
  match Document.get_sentence st.document id with
  | None ->
    log (fun () -> Printf.sprintf "ExecuteToLoc %d stops after %2.3f, sentences invalidated" id time);
    {state=Some st; events=[]; update_view=true; notification=None} (* Sentences have been invalidate, probably because the user edited while executing *)
  | Some _ ->
    log (fun () -> Printf.sprintf "ExecuteToLoc %d continues after %2.3f" id time);
    let (next, execution_state,vst_for_next_todo,events, exec_error) =
      ExecutionManager.execute st.execution_state st.document (vst_for_next_todo, [], false) task block in
    let st, block_events =
      match exec_error with
      | None -> st, []
      | Some (error_id, loc) -> 
        let st, error_range = state_before_error st error_id loc in
        let events = if block then mk_block_on_error_event error_range error_id background else [] in
        st, events
      in
    let event = Option.map (fun task -> create_execution_event background (Execute {id; vst_for_next_todo; task; started })) next in
    match event, block_events with
      | None, [] -> execution_finished { st with execution_state } id started (* There is no new tasks, and no errors -> execution finished *)
      | _ ->
        let cancel_handle = Option.map Sel.Event.get_cancellation_handle event in
        let event = match event with Some e -> [e] | None -> [] in
        (* After successful execution, run hybrid replay up to sentence for fuller goal state. *)
        let st = {st with execution_state} in
        let s_id = ExecutionManager.get_id_of_executed_task task in
        let st, _ran = hybrid_replay_up_to_sentence st s_id in
        let state = Some {st with cancel_handle} in
        let update_view = true in
        let move_cursor_event = match exec_error with None -> move_cursor_and_highlight_for_task () | Some _ -> [] in
        let events = move_cursor_event @ proof_view_event @ inject_em_events events @ block_events @ event in
        {state; events; update_view; notification=None}

let get_proof st id_opt =
  match id_opt with
  | None -> 
    Printf.eprintf "🎯 DocumentManager: get_proof called with no sentence ID\n%!";
    None
  | Some id ->
    Printf.eprintf "🎯 DocumentManager: get_proof called for sentence %s\n%!" (Document.sentence_ido_string id);
    let exec_state = st.execution_state in
    match ExecutionManager.get_context exec_state id with
    | None -> 
      Printf.eprintf "❌ DocumentManager: No context found for sentence %s\n%!" (Document.sentence_ido_string id);
      None
    | Some scope ->
      Printf.eprintf "✅ DocumentManager: Found context for sentence %s, extracting proof state\n%!" (Document.sentence_ido_string id);
      (match ProofState.get_proof ~previous:None scope with
       | None -> None
       | Some _proof_state -> Some "Proof state available")

let get_string_proof st id =
  Printf.eprintf "🎯 DocumentManager: get_string_proof called for sentence %s\n%!" (Document.sentence_ido_string id);
  match get_proof st (Some id) with
  | None -> 
    Printf.eprintf "❌ DocumentManager: No proof found for sentence %s\n%!" (Document.sentence_ido_string id);
    None
  | Some proof_string ->
    Printf.eprintf "✅ DocumentManager: Found proof state for sentence %s\n%!" (Document.sentence_ido_string id);
    Some proof_string

let handle_execution_manager_event st ev =
  let id, execution_state_update, events = ExecutionManager.handle_event ev st.execution_state in
  let st = 
    match (id, execution_state_update) with
    | Some id, Some exec_st ->
      let execution_state = ExecutionManager.update_processed id exec_st st.document in
      Some {st with execution_state}
    | Some id, None ->
      let execution_state = ExecutionManager.update_processed id st.execution_state st.document in
      Some {st with execution_state}
    | _, _ -> Option.map (fun execution_state -> {st with execution_state}) execution_state_update
  in
  let update_view = true in
  {state=st; events=(inject_em_events events); update_view; notification=None}

let handle_event ev st ~block =
  Printf.eprintf "🎯 DocumentManager: handle_event called with event\n%!";
  match ev with
  | ParseBegin ->
    Printf.eprintf "📝 DocumentManager: Handling ParseBegin event - parsing document\n%!";
    (* Actually parse the document into sentences *)
    let parsed_doc, events = Document.validate_document st.document in
    let new_state = { st with document = parsed_doc; document_state = Parsed } in
    Printf.eprintf "✅ DocumentManager: Document parsed successfully\n%!";
    {state = Some new_state; events = inject_doc_events events; update_view = true; notification = None}
  | DocumentEvent doc_event ->
    Printf.eprintf "📄 DocumentManager: Handling DocumentEvent - calling Document.handle_event\n%!";
    let updated_document, new_events, parsing_end_info = Document.handle_event st.document doc_event in
    let final_document = match parsing_end_info with
      | Some info -> 
        Printf.eprintf "🔍 DocumentManager: Using parsed_document from parsing_end_info\n%!";
        info.parsed_document
    | None ->
        Printf.eprintf "🔍 DocumentManager: Using updated_document (no parsing_end_info)\n%!";
        updated_document
    in
    let new_state = { st with document = final_document } in
    Printf.eprintf "✅ DocumentManager: DocumentEvent processed, generated %d new events\n%!" (List.length new_events);
    (* Build diagnostics notification *)
    let diag_json = build_publish_diagnostics_notification new_state in
    let notification = Yojson.Safe.to_string diag_json in
    {state = Some new_state; events = inject_doc_events new_events; update_view = true; notification = Some notification}
  | Execute { id; vst_for_next_todo; task; started } ->
    Printf.eprintf "🔧 DocumentManager: Handling Execute event for sentence %s\n%!" (Document.sentence_ido_string id);
    execute st id vst_for_next_todo started task false block
  | ExecutionManagerEvent em_event ->
    Printf.eprintf "🔧 DocumentManager: Handling ExecutionManagerEvent\n%!";
    handle_execution_manager_event st em_event
  | SendMoveCursor range ->
    Printf.eprintf "🧭 DocumentManager: Handling SendMoveCursor to %s\n%!" (Range.to_string range);
    let textDocument = Lsp.Types.VersionedTextDocumentIdentifier.create ~uri:st.uri ~version:1 in
    let notification = Protocol.ExtProtocol.Notification.Server.moveCursor textDocument range.Range.start in
    let notification_str = Yojson.Safe.to_string (Jsonrpc.Notification.yojson_of_t notification) in
    (* Also send a lightweight semantic highlight for the last executed range *)
    (* Also send a lightweight semantic highlight for the last executed range via SendHighlight event *)
    let queued = Sel.now ~priority:PriorityManager.move_cursor (SendHighlight range) in
    {state = Some st; events = [queued]; update_view = false; notification = Some notification_str}
  | SendHighlight range ->
    Printf.eprintf "✨ DocumentManager: Handling SendHighlight for %s\n%!" (Range.to_string range);
    let uri_str = st.uri in
    let tokens = [`Assoc [
      ("line", `Int range.Range.start.line);
      ("startChar", `Int range.Range.start.character);
      ("length", `Int 0);
      ("tokenType", `String "highlight");
      ("classification", `String "last-executed")
    ]] in
    let highlight_json = `Assoc [
      ("jsonrpc", `String "2.0");
      ("method", `String "vsec/semanticHighlighting");
      ("params", `Assoc [ ("uri", `String (Lsp.Types.DocumentUri.to_string uri_str)); ("tokens", `List tokens) ])
    ] in
    {state = Some st; events = []; update_view = false; notification = Some (Yojson.Safe.to_string highlight_json)}
  | ClearHighlight ->
    Printf.eprintf "🧹 DocumentManager: Handling ClearHighlight\n%!";
    let uri_str = st.uri in
    let clear_json = `Assoc [
      ("jsonrpc", `String "2.0");
      ("method", `String "vsec/semanticHighlighting");
      ("params", `Assoc [ ("uri", `String (Lsp.Types.DocumentUri.to_string uri_str)); ("tokens", `List []) ])
    ] in
    {state = Some st; events = []; update_view = false; notification = Some (Yojson.Safe.to_string clear_json)}
  | JumpToRange range ->
    let textDocument = Lsp.Types.VersionedTextDocumentIdentifier.create ~uri:st.uri ~version:1 in
    let notification = Protocol.ExtProtocol.Notification.Server.moveCursor textDocument range.Range.start in
    let notification_str = Yojson.Safe.to_string (Jsonrpc.Notification.yojson_of_t notification) in
    { state = Some st; events = []; update_view = false; notification = Some notification_str }
  | SendProofView sentence_id_opt ->
     Printf.eprintf "📤 DocumentManager: Handling SendProofView event (sentence_id: %s)\n%!" 
       (match sentence_id_opt with Some id -> string_of_int id | None -> "None");
     
     (* Extract proof state using the current execution context *)
     let proof_state = match sentence_id_opt with
       | Some sentence_id ->
         Printf.eprintf "DEBUG: SendProofView - extracting proof for sentence %d\n%!" sentence_id;
         (match ExecutionManager.get_context st.execution_state sentence_id with
          | Some scope -> 
            Printf.eprintf "DEBUG: SendProofView - found scope for sentence %d\n%!" sentence_id;
            Protocol.ProofState.get_proof ~previous:None scope
          | None -> 
            Printf.eprintf "DEBUG: SendProofView - no scope for sentence %d, using initial\n%!" sentence_id;
            let initial_scope = ExecutionManager.get_initial_context st.execution_state in
            Protocol.ProofState.get_proof ~previous:None initial_scope)
       | None ->
         Printf.eprintf "DEBUG: SendProofView - empty proof view requested (no sentence id)\n%!";
         None
     in
     
     Printf.eprintf "✅ DocumentManager: SendProofView - proof state extracted: %s\n%!" 
       (match proof_state with Some _ -> "Some proof" | None -> "None");
     
     (* If we have a real proof state, send it; otherwise try hybrid fallback or minimal derived-goal JSON payload *)
     (match proof_state with
      | Some _ ->
        let textDocument = Lsp.Types.VersionedTextDocumentIdentifier.create ~uri:st.uri ~version:1 in
        let proof_notification = Protocol.ExtProtocol.Notification.Server.proofView textDocument proof_state in
        let proof_json = Jsonrpc.Notification.yojson_of_t proof_notification in
        let notification_str = Yojson.Safe.to_string proof_json in
        {state = Some st; events = []; update_view = true; notification = Some notification_str}
      | None ->
        (* Try hybrid fallback first: if we have a previously captured hybrid proof json, send it *)
        let hybrid_json_opt =
          match sentence_id_opt with
          | Some sid -> ExecutionManager.hybrid_proof_for_sentence st.execution_state sid
          | None -> None
        in
        match hybrid_json_opt with
        | Some proof_json ->
          (* Prefer hybrid proof JSON as-is when it already contains goals. Only attach raw output if no goals present. *)
          let raw_out = ExecutionManager.get_last_easycrypt_raw_output () in
          let enriched =
            (match proof_json with
             | `Assoc fields ->
               begin match List.assoc_opt "params" fields with
               | Some (`Assoc pfields) ->
                 (* Inspect goals length inside proofState *)
                 let has_goals =
                   match List.assoc_opt "proofState" pfields with
                   | Some (`Assoc ps_fields) ->
                     (match List.assoc_opt "goals" ps_fields with
                      | Some (`List (_ :: _)) -> true
                      | _ -> false)
                   | _ -> false
                 in
                 if has_goals || String.length raw_out = 0 then
                   proof_json
                 else
                   let messages = `List [ `Assoc [("level", `String "info"); ("text", `String raw_out)] ] in
                   let pfields = List.remove_assoc "messages" pfields in
                   let new_params = `Assoc (("messages", messages) :: pfields) in
                   `Assoc (("params", new_params) :: (List.remove_assoc "params" fields))
               | _ -> proof_json
               end
             | _ -> proof_json)
          in
          let notification_str = Yojson.Safe.to_string enriched in
          {state = Some st; events = []; update_view = true; notification = Some notification_str}
        | None ->
        (* Derive a goal string from nearest previous lemma definition *)
        let extract_goal_string s =
          try
            let txt = Document.Internal.string_of_sentence s in
            if String.length txt = 0 then None else
            let lower = String.lowercase_ascii txt in
            if not (String.contains lower ':') then None else
            let idx_colon = String.index lower ':' in
            let idx_dot = try String.rindex lower '.' with Not_found -> String.length lower - 1 in
            if idx_dot <= idx_colon then None else
            let goal = String.sub txt (idx_colon + 1) (idx_dot - idx_colon - 1) |> String.trim in
            Some goal
          with _ -> None
        in
        let rec find_prev_lemma before_loc attempts =
          if attempts <= 0 then None else
          match Document.find_sentence_before st.document before_loc with
          | None -> None
          | Some s ->
            (match s.ast with
             | Error _ -> find_prev_lemma (s.start - 1) (attempts - 1)
             | Parsed p ->
               (match p.classification with
                | EasyCryptClassification.EcDefinition ->
                  (match extract_goal_string s with
                   | Some g -> Some g
                   | None -> find_prev_lemma (s.start - 1) (attempts - 1))
                | _ -> find_prev_lemma (s.start - 1) (attempts - 1)))
        in
        let start_loc = match sentence_id_opt with
          | Some id -> (match Document.get_sentence st.document id with | Some s -> s.start | None -> 0)
          | None -> 0
        in
        (match find_prev_lemma start_loc 20 with
         | None -> Printf.eprintf "📤 DocumentManager: No proof to send after fallback\n%!"; {state = Some st; events = []; update_view = true; notification = None}
         | Some goal_string ->
           let uri_str = Lsp.Types.DocumentUri.to_string st.uri in
           let td_json : Yojson.Safe.t = `Assoc [ ("uri", `String uri_str); ("version", `Int 1) ] in
           let proof_json : Yojson.Safe.t = `Assoc [
             ("goals", `List [ `Assoc [("id", `Int 1); ("hypotheses", `List []); ("goal", `String goal_string)] ]);
             ("shelvedGoals", `List []);
             ("givenUpGoals", `List []);
             ("unfocusedGoals", `List []);
             ("navigation", `Null);
             ("current_lemma", `Null);
             ("proof_progress", `Float 0.0)
           ] in
           let notif_json : Yojson.Safe.t = `Assoc [
             ("jsonrpc", `String "2.0");
             ("method", `String "prover/proofView");
             ("params", `Assoc [ ("textDocument", td_json); ("proofState", proof_json) ])
           ] in
           let notification_str = Yojson.Safe.to_string notif_json in
           {state = Some st; events = []; update_view = true; notification = Some notification_str}))
  | _ ->
    Printf.eprintf "⚠️ DocumentManager: Unhandled event, using default behavior\n%!";
    (* Default behavior for other events *)
    {state = Some st; events = []; update_view = false; notification = None}

let context_of_id st = function
  | None -> Some (ExecutionManager.get_initial_context st.execution_state)
  | Some id -> ExecutionManager.get_context st.execution_state id

(** Get context at the start of the sentence containing [pos] *)
let get_context st pos = context_of_id st (id_of_pos st pos)

let get_completions st pos =
  (* EasyCrypt stub - completion options not implemented yet *)
  []

(* EasyCrypt stub - Coq parsing not needed *)
let parse_entry st pos entry pattern =
  (* Minimal stub for EasyCrypt - returns empty result *)
  (pattern, [])

(* EasyCrypt stub - Pcoq not needed *)
let smart_global = ref (fun _ -> "")

let about st pos ~pattern =
  (* EasyCrypt stub - Coq context handling not implemented yet *)
  Error ({message="About functionality not implemented for EasyCrypt"; code=None})

let search st ~id pos pattern =
  (* EasyCrypt stub - search functionality not implemented yet *)
  []

(** Try to generate hover text from [pattern] the context of the given [sentence] *)
let hover_of_sentence st loc pattern sentence = 
  (* EasyCrypt stub - hover functionality not implemented yet *)
      None

let hover st pos =
  (* EasyCrypt stub - hover functionality not implemented yet *)
  None

(* EasyCrypt stub - Pcoq not needed *)
let lconstr = ref (fun _ -> "")


let jump_to_definition _  _ = None

let check st pos ~pattern =
  (* EasyCrypt stub - check functionality not implemented yet *)
  Error ({message="Check functionality not implemented for EasyCrypt"; code=None})

(* EasyCrypt stub - Prettyp not needed *)
let print_located_qualid _ _qid = "Located"

let locate st pos ~pattern = 
  (* EasyCrypt stub - locate functionality not implemented yet *)
  Error ({message="Locate functionality not implemented for EasyCrypt"; code=None})

(* EasyCrypt stub - Prettyp not needed *)
let print_name _ _ _ _ = "PrintName"

let print st pos ~pattern = 
  (* EasyCrypt stub - print functionality not implemented yet *)
  Error ({message="Print functionality not implemented for EasyCrypt"; code=None})

(* EasyCrypt stub - Coq warning system not needed *)
let warn_nested_proofs_opt () = ()

let () = (* EasyCrypt - no option system needed *) ()

module Internal = struct

  let document st =
    st.document

  let raw_document st = 
    Document.raw_document st.document

  let execution_state st =
    st.execution_state

  let observe_id st =
    match st.observe_id with
    | Top -> None
    | (Id id) -> Some id

  let validate_document st parsing_end_info = validate_document st parsing_end_info

  let string_of_state st =
    let code_lines_by_id = Document.code_lines_sorted_by_loc st.document in
    let code_lines_by_end = Document.code_lines_by_end_sorted_by_loc st.document in
    let string_of_state id =
      if ExecutionManager.is_locally_executed st.execution_state id then "(executed)"
      else if ExecutionManager.is_remotely_executed st.execution_state id then "(executed in worker)"
      else "(not executed)"
    in
    let string_of_item item =
      Document.Internal.string_of_item item ^ " " ^
        match item with
        | Sentence { id } -> string_of_state id
        | ParsingError _ -> "(error)"
        | Comment _ -> "(comment)"
    in
    let string_by_id = String.concat "\n" @@ List.map string_of_item code_lines_by_id in
    let string_by_end = String.concat "\n" @@ List.map string_of_item code_lines_by_end in
    String.concat "\n" ["Document using sentences_by_id map\n"; string_by_id; "\nDocument using sentences_by_end map\n"; string_by_end]
    let inject_doc_events = inject_doc_events

end
