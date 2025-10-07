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
  nav_history: Protocol.ProofState.proof_step_info list;
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
    make_diagnostic st.document (Document.range_of_id st.document id) oloc (`String msg) (DiagnosticSeverity.to_lsp lvl) code

let mk_error_diag st (id,(oloc,msg,qf)) = (* mk_diag st (id,(Feedback.Error,oloc, msg)) *)
  let code = 
    (* EasyCrypt doesn't use Coq's Quickfix system *)
    match qf with
    | None -> None
    | Some _qf -> None (* Simplified for EasyCrypt - no quickfix support *)
  in
  make_diagnostic st.document (Document.range_of_id st.document id) oloc (`String msg) (DiagnosticSeverity.to_lsp DiagnosticSeverity.Error) code


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
  let feedback_converted = List.map (fun (id, (lvl_lsp, oloc, msg)) ->
    let lvl = match lvl_lsp with
      | Lsp.Types.DiagnosticSeverity.Error -> DiagnosticSeverity.Error
      | Lsp.Types.DiagnosticSeverity.Warning -> DiagnosticSeverity.Warning
      | Lsp.Types.DiagnosticSeverity.Information -> DiagnosticSeverity.Information
      | Lsp.Types.DiagnosticSeverity.Hint -> DiagnosticSeverity.Hint
    in
    (id, (lvl, oloc, [], msg))
  ) feedback in
  List.map (mk_parsing_error_diag st) parse_errors @
    List.map (mk_error_diag st) exec_errors @
    List.map (fun (id, (lvl, oloc, qf, msg)) -> mk_diag st (id, (lvl, oloc, qf, msg))) feedback_converted

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
  let feedback = List.map (fun (lvl,_oloc,msg) -> lvl, msg) feedback  in
  match error with
  | Some (_oloc,msg) -> (Lsp.Types.DiagnosticSeverity.Error, msg) :: feedback
  | None -> feedback

let get_string_messages st id =
  let error = ExecutionManager.error st.execution_state id in
  let feedback = ExecutionManager.feedback st.execution_state id in
  let conv = function
    | Lsp.Types.DiagnosticSeverity.Error -> DiagnosticSeverity.Error
    | Lsp.Types.DiagnosticSeverity.Warning -> DiagnosticSeverity.Warning
    | Lsp.Types.DiagnosticSeverity.Information -> DiagnosticSeverity.Information
    | Lsp.Types.DiagnosticSeverity.Hint -> DiagnosticSeverity.Hint
  in
  let feedback = List.map (fun (lvl,_oloc,msg) -> conv lvl, msg) feedback  in
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
    List.map (fun (lvl,_oloc,msg) -> lvl, msg) feedback

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

let observe ~background state id ~should_block_on_error : (state * event Sel.Event.t list) =
  match Document.get_sentence state.document id with
  | None -> state, [] (* TODO error? *)
  | Some { id } ->
    Option.iter Sel.Event.cancel state.cancel_handle;
    let vst_for_next_todo, execution_state, task, error_id = ExecutionManager.build_tasks_for state.document (Document.schedule state.document) state.execution_state id should_block_on_error in
    match task with
    | Some task -> (* task will only be Some if there is no error *)
        let event = create_execution_event background (Execute {id; vst_for_next_todo; task; started = Unix.gettimeofday ()}) in
        let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
        (* Forward navigation: update observe_id immediately to the target sentence *)
        let state = { state with execution_state; cancel_handle; observe_id = Id id } in
        state, [event]
    | None ->
      match error_id with
      | None ->
        (* Nothing to execute (already up-to-date) — still advance observe_id to target *)
        { state with execution_state; observe_id = Id id }, []
      | Some (error_id, loc) ->
        let state, error_range = state_before_error state error_id loc in
        let events = mk_block_on_error_event error_range error_id background in
        {state with execution_state}, events

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

let jump_to_definition st pos =
  (* Robustly find word near cursor and match to outline names; consult env and symbol index; handle dotted names *)
  let raw = Document.raw_document st.document in
  let rec word_at_or_backoff p attempts =
    if attempts > 3 then None else
    match RawDocument.word_at_position raw p with
    | Some w -> Some w
    | None ->
      let Position.{ line; character } = p in
      let character' = if character = 0 then 0 else character - 1 in
      word_at_or_backoff (Position.create ~line ~character:character') (attempts + 1)
  in
  let try_outline name =
    let lname = String.lowercase_ascii name in
    let outline = Document.outline st.document in
    let rec find = function
      | [] -> None
      | (e:Document.outline_element) :: tl ->
        if String.lowercase_ascii e.name = lname then Some e.range else find tl
    in find outline
  in
  let try_symbol_index name =
    match ExecutionManager.lookup_symbol_def st.execution_state name with
    | Some (_sid, Some range) -> Some range
    | Some (_sid, None) ->
      (* Approximate by returning the current/next sentence range *)
      (match id_of_pos st pos with
      | None -> None
      | Some sid ->
        match Document.get_sentence st.document sid with
        | None -> None
        | Some { stop } ->
          (match Document.find_sentence_after st.document (stop+1) with
          | None -> Some (Document.range_of_id st.document sid)
          | Some { id = next_id } -> Some (Document.range_of_id st.document next_id)))
    | None -> None
  in
  let normalize_candidates (w:string) : string list =
    let w = String.trim w in
    if String.length w = 0 then [] else
    let base = w in
    let suffix = try
      let idx = String.rindex w '.' in
      if idx + 1 < String.length w then String.sub w (idx+1) (String.length w - idx - 1) else w
    with Not_found -> w
    in
    if String.equal (String.lowercase_ascii base) (String.lowercase_ascii suffix)
    then [base]
    else [base; suffix]
  in
  match word_at_or_backoff pos 0 with
  | None -> None
  | Some word ->
    let candidates = normalize_candidates word in
    (* 1) Try exact outline match on any candidate *)
    let outline_hit =
      List.find_map (fun n -> try_outline n) candidates
    in
    begin match outline_hit with
    | Some r -> Some (r, word)
    | None ->
      (* 2) Consult EasyCrypt env to avoid jumping for locals/prog vars *)
      let is_env_local_or_prog =
        match id_of_pos st pos with
        | None -> false
        | Some sid ->
          begin match ExecutionManager.get_easycrypt_state st.execution_state sid with
          | None -> false
          | Some scope ->
            let env =
              match ExecutionManager.get_env_of_sentence st.execution_state sid with
              | Some e -> e
              | None -> EcLib.EcScope.env scope
            in
            let has_local = List.exists (fun n -> try EcLib.EcEnv.Var.lookup_local_opt n env <> None with _ -> false) candidates in
            if has_local then true else
            let has_prog = List.exists (fun n ->
              try (EcLib.EcEnv.Var.lookup_progvar_opt ([], n) env) <> None with _ -> false) candidates in
            has_prog
          end
      in
      if is_env_local_or_prog then None else
      (* 3) Try range-aware symbol index using candidates *)
      let idx_hit = List.find_map (fun n -> try_symbol_index n) candidates in
      match idx_hit with
      | Some r -> Some (r, word)
      | None -> None
    end

let interpret_to st id check_mode =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

let interpret_to_next_position st pos =
  match id_of_sentence_after_pos st pos with
  | None -> st, []
  | Some id ->
    observe ~background:false st id ~should_block_on_error:true

let interpret_to_position st pos =
  (* Ensure we execute up to the sentence that contains pos (or just before),
     so lemma/proof openers are included before mid-proof tactics. *)
  match id_of_pos st pos with
  | Some id -> observe ~background:false st id ~should_block_on_error:true
  | None -> interpret_to_next_position st pos

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
  (* Retract/reset to previous sentence robustly *)
  match st.observe_id with
  | Top -> st, []
  | Id id ->
    begin match Document.get_sentence st.document id with
    | None -> st, []
    | Some { start } ->
      (* Find previous sentence before current one *)
      let prev_id_opt =
        match Document.find_sentence_before st.document start with
        | None -> None
        | Some { id = prev_id } -> Some prev_id
      in
      (* Invalidate current sentence execution and dependents *)
      let exec_st = ExecutionManager.invalidate st.document (Document.schedule st.document) id st.execution_state in
      let exec_st = ExecutionManager.reset_overview exec_st st.document in
      let observe_id = match prev_id_opt with None -> Top | Some pid -> Id pid in
      { st with execution_state = exec_st; observe_id; cancel_handle = None }, []
    end

let interpret_to_next st =
  match Document.get_last_sentence st.document with
  | None -> st, []
  | Some { id } -> observe ~background:false st id ~should_block_on_error:true

let interpret_to_end st =
  match Document.get_last_sentence st.document with
  | None -> st, []
  | Some { id } -> observe ~background:false st id ~should_block_on_error:true

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
  (* EasyCrypt stub - simplified initialization *)
  let document = Document.create_document init_vs text in
  let execution_state, feedback = ExecutionManager.init init_vs in
  let opts = [] in (* Default empty options for EasyCrypt *)
  let state = { uri; opts; init_vs; document; execution_state; observe_id=Top; cancel_handle = None; document_state = Parsing; nav_history = [] } in
  let priority = Some PriorityManager.launch_parsing in
  let event = Sel.now ?priority ParseBegin in
  state, [event] @ [inject_em_event feedback]

let reset { uri; opts; init_vs; document; execution_state; } =
  (* EasyCrypt stub - simplified reset *)
  let text = RawDocument.text @@ Document.raw_document document in
  let document = Document.create_document init_vs text in
  ExecutionManager.destroy execution_state;
  let execution_state, feedback = ExecutionManager.init init_vs in
  let observe_id = Top in
  let state = { uri; opts; init_vs; document; execution_state; observe_id; cancel_handle = None ; document_state = Parsing; nav_history = [] } in
  let priority = Some PriorityManager.launch_parsing in
  let event = Sel.now ?priority ParseBegin in
  state, [event] @ [inject_em_event feedback]

let apply_text_edits state edits =
  (* Cancel any ongoing execution/parsing to reconcile with new edits *)
  Option.iter Sel.Event.cancel state.cancel_handle;
  let state = { state with cancel_handle = None } in
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
  state, [sel_event]

let execution_finished st id started =
  let time = Unix.gettimeofday () -. started in
  log (fun () -> Printf.sprintf "ExecuteToLoc %d ends after %2.3f" id time);
  (* We update the state to trigger a publication of diagnostics *)
  let update_view = true in
  let state = Some st in
  {state; events=[]; update_view; notification=None}

let execute st id vst_for_next_todo started task background block =
  let time = Unix.gettimeofday () -. started in
  let proof_view_event =
    match st.observe_id with
    | Top -> []
    | Id o_id -> [mk_proof_view_event o_id]
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
        let state = Some {st with execution_state; cancel_handle} in
        let update_view = true in
        let events = proof_view_event @ inject_em_events events @ block_events @ event in
        {state; events; update_view; notification=None}

let get_proof st id =
  match id with
  | None -> 
    let pp_goals_result = ExecutionManager.get_current_goals_pp st.execution_state in
    begin match pp_goals_result with
    | Ok goals when List.length goals > 0 ->
      let nav = if st.nav_history = [] then None else Some { Protocol.ProofState.
        current_step = List.length st.nav_history;
        total_steps = List.length st.nav_history;
        can_step_forward = true;
        can_step_backward = (List.length st.nav_history) > 1;
        step_history = st.nav_history } in
      Some { Protocol.ProofState.
        goals;
        shelvedGoals = [];
        givenUpGoals = [];
        unfocusedGoals = [];
        navigation = nav;
        current_lemma = None;
        proof_progress = 0.0;
        in_proof = true;
        error_message = None;
      }
    | Error error_msg ->
      (* Return proof state with error message *)
      Some { Protocol.ProofState.
        goals = [];
        shelvedGoals = [];
        givenUpGoals = [];
        unfocusedGoals = [];
        navigation = None;
        current_lemma = None;
        proof_progress = 0.0;
        in_proof = false;
        error_message = Some error_msg;
      }
    | Ok [] ->
      (* Adapter returned empty goals - try text fallback *)
      let goals = ExecutionManager.get_current_goals_text st.execution_state in
      if List.length goals = 0 then 
        (* No goals from either source - show diagnostic *)
        Some { Protocol.ProofState.
          goals = [];
          shelvedGoals = [];
          givenUpGoals = [];
          unfocusedGoals = [];
          navigation = None;
          current_lemma = None;
          proof_progress = 0.0;
          in_proof = false;
          error_message = Some "Adapter loaded but returned empty goals. Text fallback also empty. Are you in a proof?";
        }
      else
        Some (Protocol.ProofState.of_strings goals)
    end
  | Some id ->
    let pp_goals_result = ExecutionManager.get_current_goals_pp st.execution_state in
    begin match pp_goals_result with
    | Ok pp_goals when List.length pp_goals > 0 ->
      let nav = if st.nav_history = [] then None else Some { Protocol.ProofState.
        current_step = List.length st.nav_history;
        total_steps = List.length st.nav_history;
        can_step_forward = true;
        can_step_backward = (List.length st.nav_history) > 1;
        step_history = st.nav_history } in
      Some { Protocol.ProofState.
        goals = pp_goals;
        shelvedGoals = [];
        givenUpGoals = [];
        unfocusedGoals = [];
        navigation = nav;
        current_lemma = None;
        proof_progress = 0.0;
        in_proof = true;
        error_message = None;
      }
    | Error error_msg ->
      (* Return proof state with error message *)
      Some { Protocol.ProofState.
        goals = [];
        shelvedGoals = [];
        givenUpGoals = [];
        unfocusedGoals = [];
        navigation = None;
        current_lemma = None;
        proof_progress = 0.0;
        in_proof = false;
        error_message = Some error_msg;
      }
    | Ok [] ->
      (* Adapter returned empty goals - try text fallback *)
      let goals = ExecutionManager.get_current_goals_text st.execution_state in
      if List.length goals = 0 then 
        (* No goals from either source - show diagnostic *)
        Some { Protocol.ProofState.
          goals = [];
          shelvedGoals = [];
          givenUpGoals = [];
          unfocusedGoals = [];
          navigation = None;
          current_lemma = None;
          proof_progress = 0.0;
          in_proof = false;
          error_message = Some "Adapter loaded but returned empty goals (with id). Text fallback also empty.";
        }
      else
        Some (Protocol.ProofState.of_strings goals)
    end

let get_string_proof st id =
  (* EasyCrypt stub - PpProofState module not implemented yet *)
  None

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
  match ev with
  | ParseBegin ->
    let document, events = Document.validate_document st.document in
    let st = { st with document; document_state = Parsing } in
    { state = Some st; events = inject_doc_events events; update_view = false; notification = None }
  | DocumentEvent doc_event ->
    let document, events, parsing_end_info_opt = Document.handle_event st.document doc_event in
    begin match parsing_end_info_opt with
    | None ->
      let st = { st with document } in
      { state = Some st; events = inject_doc_events events; update_view = false; notification = None }
    | Some parsing_end_info ->
      let st = validate_document { st with document } parsing_end_info in
      { state = Some st; events = inject_doc_events events; update_view = true; notification = None }
    end
  | ExecutionManagerEvent em_event ->
    handle_execution_manager_event st em_event
  | Observe id ->
    let st, events = observe ~background:false st id ~should_block_on_error:block in
    { state = Some st; events; update_view = true; notification = None }
  | Execute { id; vst_for_next_todo; task; started } ->
    execute st id vst_for_next_todo started task (* background: *) false (* block: *) block
  | SendProofView id_opt ->
    { state = Some st; events = []; update_view = true; notification = None }
  | SendBlockOnError _ ->
    { state = Some st; events = []; update_view = true; notification = None }
  | SendMoveCursor _ ->
    { state = Some st; events = []; update_view = false; notification = None }

let context_of_id st = function
  | None -> Some (ExecutionManager.get_initial_context st.execution_state)
  | Some id -> ExecutionManager.get_context st.execution_state id

(** Get context at the start of the sentence containing [pos] *)
(* Extract completions from EasyCrypt scope *)
let extract_completions_from_easycrypt_scope scope prefix =
  try
    let env = EcLib.EcScope.env scope in
    (* Extract available identifiers from the EasyCrypt environment *)
    (* This would use EcLib APIs to get symbols, lemmas, tactics, etc. *)
    let mk name typ detail = CompletionItems.mk_completion_item name typ detail in
    
    (* For now, return some basic completions based on EasyCrypt patterns *)
    let basic_completions = [
      mk (prefix ^ "_lemma") "identifier" "EasyCrypt lemma";
      mk (prefix ^ "_theorem") "identifier" "EasyCrypt theorem";
    ] in
    
    (* TODO: Use real EcLib APIs to extract actual symbols from environment *)
    (* In a full implementation, we would:
       - Query EcLib.EcEnv for available identifiers
       - Extract module definitions
       - Get current proof context
       - List available tactics based on current goal
    *)
    basic_completions
  with
  | exn ->
    (* Log error but don't fail completion *)
    log (fun () -> Printf.sprintf "Warning: Failed to extract EasyCrypt completions: %s" (Printexc.to_string exn));
    []

let get_context st pos = context_of_id st (id_of_pos st pos)

let get_completions st pos =
  let raw = Document.raw_document st.document in
  let prefix_opt = RawDocument.word_at_position raw pos in
  let prefix = Option.value ~default:"" prefix_opt |> String.lowercase_ascii in
  let mk name typ detail = CompletionItems.mk_completion_item name typ detail in
  (* Base EasyCrypt keywords and tactics *)
  let keywords = [
    mk "lemma" "keyword" "Introduce a lemma";
    mk "theorem" "keyword" "Introduce a theorem";
    mk "axiom" "keyword" "Introduce an axiom";
    mk "module" "keyword" "Start a module";
    mk "theory" "keyword" "Start a theory";
    mk "require" "keyword" "Require libraries";
    mk "import" "keyword" "Import libraries";
    mk "proof" "keyword" "Begin proof block";
    mk "qed" "keyword" "End proof block";
  ] in
  let tactics = [
    mk "intros" "tactic" "Introduce variables and hypotheses";
    mk "apply" "tactic" "Apply a lemma or hypothesis";
    mk "rewrite" "tactic" "Rewrite using an equality";
    mk "unfold" "tactic" "Unfold a definition";
    mk "simplify" "tactic" "Simplify expressions";
    mk "split" "tactic" "Split conjunction/equivalence";
    mk "auto" "tactic" "Automatic proof search";
    mk "trivial" "tactic" "Try trivial methods";
  ] in
  (* Environment-driven identifiers from current EasyCrypt scope *)
  let env_idents =
    let scope = ExecutionManager.get_current_scope st.execution_state in
    let env_completions = extract_completions_from_easycrypt_scope scope prefix in
    env_completions @
    (match id_of_pos st pos with
    | None -> []
    | Some id ->
      begin match ExecutionManager.get_easycrypt_state st.execution_state id with
      | None -> []
      | Some scope -> 
        (* Extract context-specific completions from scope *)
        try
          let _ = EcLib.EcScope.env scope in
          (* Collect module, theory, and symbol names heuristically *)
          let names = ref [] in
          (* Modules/Theories from outline to complement env *)
          let outline = Document.outline st.document in
          List.iter (fun (e:Document.outline_element) ->
            names := e.name :: !names
          ) outline;
          (* Deduplicate and convert to completion items *)
          let uniq = List.sort_uniq String.compare !names in
          List.map (fun n -> mk n "identifier" "From current document") uniq
        with _ -> []
      end)
  in
  let items = keywords @ tactics @ env_idents in
  let starts_with s p =
    let s = String.lowercase_ascii s in
    String.length p = 0 || (String.length s >= String.length p && String.sub s 0 (String.length p) = p)
  in
  List.filter (fun (i:CompletionItems.completion_item) -> starts_with i.name prefix) items

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
  let raw = Document.raw_document st.document in
  let rec word_at_or_backoff p attempts =
    if attempts > 3 then None else
    match RawDocument.word_at_position raw p with
    | Some w -> Some w
    | None ->
      let Position.{ line; character } = p in
      let character' = if character = 0 then 0 else character - 1 in
      word_at_or_backoff (Position.create ~line ~character:character') (attempts + 1)
  in
  let mk_md s = Some (MarkupContent.create ~kind:MarkupKind.Markdown ~value:s) in
  let normalize_candidates (w:string) : string list =
    let w = String.trim w in
    if String.length w = 0 then [] else
    let base = w in
    let suffix = try
      let idx = String.rindex w '.' in
      if idx + 1 < String.length w then String.sub w (idx+1) (String.length w - idx - 1) else w
    with Not_found -> w in
    if String.equal (String.lowercase_ascii base) (String.lowercase_ascii suffix)
    then [base] else [base; suffix]
  in
  match word_at_or_backoff pos 0 with
  | None -> None
  | Some word ->
    (* 1) Try sentence env: locals/prog vars pretty-printed *)
    let env_hover =
      match id_of_pos st pos with
      | None -> None
      | Some sid ->
        begin match ExecutionManager.get_easycrypt_state st.execution_state sid with
        | None -> None
        | Some scope ->
          let env = match ExecutionManager.get_env_of_sentence st.execution_state sid with Some e -> e | None -> EcLib.EcScope.env scope in
          let ppe = EcLib.EcPrinting.PPEnv.ofenv env in
          let is_local = try EcLib.EcEnv.Var.lookup_local_opt word env <> None with _ -> false in
          if is_local then mk_md (Printf.sprintf "`%s` – local variable" word) else
          match (try EcLib.EcEnv.Var.lookup_progvar_opt ([], word) env with _ -> None) with
          | Some (`Var pv, _ty) -> mk_md (Format.asprintf "`%s` – program variable %a" word (EcLib.EcPrinting.pp_pv ppe) pv)
          | Some (`Proj (pv, _), _ty) -> mk_md (Format.asprintf "`%s` – program variable %a" word (EcLib.EcPrinting.pp_pv ppe) pv)
          | None -> None
        end
    in
    match env_hover with
    | Some _ as r -> r
    | None ->
      (* 2) Try declaration via symbol index/AST: show declaration snippet *)
      let candidates = normalize_candidates word in
      let decl_md =
        let rec try_names = function
          | [] -> None
          | name :: tl ->
            begin match ExecutionManager.lookup_symbol_def st.execution_state name with
            | Some (sid, _range_opt) ->
              let ast = ExecutionManager.get_ast_of_sentence st.execution_state sid in
              let outline_stmt =
                let lname = String.lowercase_ascii name in
                let o = Document.outline st.document in
                match List.find_opt (fun (e:Document.outline_element) -> String.equal (String.lowercase_ascii e.name) lname) o with
                | Some e -> Some e.statement | None -> None
              in
              let code = match ast with Some a -> String.trim a | None -> (match outline_stmt with Some s -> s | None -> name) in
              let md = Printf.sprintf "**%s**\n\n```easycrypt\n%s\n```" name code in
              mk_md md
            | None -> try_names tl
            end
        in
        try_names candidates
      in
      begin match decl_md with
      | Some _ as r -> r
      | None ->
        (* 3) Fallback: simple classification *)
        let w = String.lowercase_ascii word in
        let value =
          if List.mem w ["lemma"; "theorem"; "axiom"] then Printf.sprintf "**%s** – definition keyword" word
          else if List.mem w ["proof"; "qed"] then Printf.sprintf "**%s** – proof keyword" word
          else if List.mem w ["apply"; "rewrite"; "unfold"; "simplify"; "auto"; "intros"; "split"; "trivial"] then Printf.sprintf "**%s** – tactic" word
          else Printf.sprintf "**%s** – symbol" word in
        mk_md value
      end

(* EasyCrypt stub - Pcoq not needed *)
let lconstr = ref (fun _ -> "")


let jump_to_definition _  _ = None
let jump_to_definition st pos =
  let raw = Document.raw_document st.document in
  let rec word_at_or_backoff p attempts =
    if attempts > 3 then None else
    match RawDocument.word_at_position raw p with
    | Some w -> Some w
    | None ->
      let Position.{ line; character } = p in
      let character' = if character = 0 then 0 else character - 1 in
      word_at_or_backoff (Position.create ~line ~character:character') (attempts + 1)
  in
  let normalize_candidates (w:string) : string list =
    let w = String.trim w in
    if String.length w = 0 then [] else
    let base = w in
    let suffix = try
      let idx = String.rindex w '.' in
      if idx + 1 < String.length w then String.sub w (idx+1) (String.length w - idx - 1) else w
    with Not_found -> w
    in
    if String.equal (String.lowercase_ascii base) (String.lowercase_ascii suffix)
    then [base]
    else [base; suffix]
  in
  match word_at_or_backoff pos 0 with
  | None -> None
  | Some word ->
    let candidates = normalize_candidates word in
    let try_outline name =
      let lname = String.lowercase_ascii name in
      let outline = Document.outline st.document in
      let rec find = function
        | [] -> None
        | (e:Document.outline_element) :: tl ->
          if String.lowercase_ascii e.name = lname then Some e.range else find tl
      in find outline
    in
    let try_symbol_index name =
      match ExecutionManager.lookup_symbol_def st.execution_state name with
      | Some (_sid, Some range) -> Some range
      | Some (_sid, None) ->
        (match get_next_range st pos with Some r -> Some r | None -> None)
      | None -> None
    in
    (* Prefer outline hit *)
    (match List.find_map try_outline candidates with
    | Some r -> Some (r, word)
    | None ->
      (* Avoid jumping for locals/prog vars *)
      let is_env_local_or_prog =
        match id_of_pos st pos with
        | None -> false
        | Some sid ->
          begin match ExecutionManager.get_easycrypt_state st.execution_state sid with
          | None -> false
          | Some scope ->
            let env =
              match ExecutionManager.get_env_of_sentence st.execution_state sid with
              | Some e -> e
              | None -> EcLib.EcScope.env scope
            in
            let has_local = List.exists (fun n -> try EcLib.EcEnv.Var.lookup_local_opt n env <> None with _ -> false) candidates in
            if has_local then true else
            let has_prog = List.exists (fun n -> try EcLib.EcEnv.Var.lookup_progvar_opt ([], n) env <> None with _ -> false) candidates in
            has_prog
          end
      in
      if is_env_local_or_prog then None else
      match List.find_map try_symbol_index candidates with
      | Some r -> Some (r, word)
      | None -> None)

let references st pos =
  let raw = Document.raw_document st.document in
  let word_opt = RawDocument.word_at_position raw pos in
  match word_opt with
  | None -> []
  | Some word ->
    let text = RawDocument.text raw in
    let lines = String.split_on_char '\n' text in
    let is_word_char = function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true | _ -> false in
    let wlen = String.length word in
    let lower_word = String.lowercase_ascii word in
    let results = ref [] in
    List.iteri (fun line_idx line ->
      let lower_line = String.lowercase_ascii line in
      let rec search_from i =
        if i < 0 || i >= String.length lower_line then () else
        match String.index_from_opt lower_line i (String.get lower_word 0) with
        | None -> ()
        | Some j ->
          if j + wlen <= String.length lower_line && String.sub lower_line j wlen = lower_word then (
            let before_ok = if j = 0 then true else not (is_word_char lower_line.[j-1]) in
            let after_ok = if j + wlen >= String.length lower_line then true else not (is_word_char lower_line.[j+wlen]) in
            if before_ok && after_ok then (
              let start = Position.create ~line:line_idx ~character:j in
              let end_ = Position.create ~line:line_idx ~character:(j + wlen) in
              results := (Range.create ~start ~end_) :: !results
            );
            search_from (j + wlen)
          ) else search_from (j + 1)
      in
      search_from 0
    ) lines;
    List.rev !results

let check st pos ~pattern =
  let raw = Document.raw_document st.document in
  let word = match RawDocument.word_at_position raw pos with Some w -> w | None -> pattern in
  (* Try EC lookup; fallback to echo *)
  let detail =
    match id_of_pos st pos with
    | None -> None
    | Some id ->
      begin match ExecutionManager.get_easycrypt_state st.execution_state id with
      | None -> None
      | Some scope ->
        let env = EcLib.EcScope.env scope in
        let is_local = try EcLib.EcEnv.Var.lookup_local_opt word env <> None with _ -> false in
        let is_prog  = try EcLib.EcEnv.Var.lookup_progvar_opt ([], word) env <> None with _ -> false in
        if is_local then Some ("local variable: " ^ word)
        else if is_prog then Some ("program variable: " ^ word)
        else
          (* Fallback: check outline names as proxy for declarations in this doc *)
          let target = String.lowercase_ascii word in
          let in_outline = List.exists (fun (e:Document.outline_element) -> String.equal (String.lowercase_ascii e.name) target) (Document.outline st.document) in
          if in_outline then Some ("symbol " ^ word ^ " is declared in this document") else None
      end
  in
  Ok (match detail with Some d -> d | None -> ("Check: " ^ word))

(* EasyCrypt stub - Prettyp not needed *)
let print_located_qualid _ _qid = "Located"

let locate st pos ~pattern = 
  let raw = Document.raw_document st.document in
  let word = match RawDocument.word_at_position raw pos with Some w -> w | None -> pattern in
  (* Try environment first, then outline *)
  let env_result =
    match id_of_pos st pos with
    | None -> None
    | Some id ->
      begin match ExecutionManager.get_easycrypt_state st.execution_state id with
      | None -> None
      | Some scope ->
        let env = EcLib.EcScope.env scope in
        let is_local = try EcLib.EcEnv.Var.lookup_local_opt word env <> None with _ -> false in
        let is_prog  = try EcLib.EcEnv.Var.lookup_progvar_opt ([], word) env <> None with _ -> false in
        if is_local then Some ("Located local variable: " ^ word)
        else if is_prog then Some ("Located program variable: " ^ word)
        else None
      end
  in
  match env_result with
  | Some s -> Ok s
  | None ->
    let target = String.lowercase_ascii word in
    let outline = Document.outline st.document in
    let found = List.find_opt (fun (e:Document.outline_element) -> String.equal (String.lowercase_ascii e.name) target) outline in
    (match found with
    | Some e -> Ok (Printf.sprintf "Located %s at %s" word (Range.to_string e.range))
    | None -> Ok ("Locate: " ^ word))

(* EasyCrypt stub - Prettyp not needed *)
let print_name _ _ _ _ = "PrintName"

let print st pos ~pattern = 
  let raw = Document.raw_document st.document in
  let word = match RawDocument.word_at_position raw pos with Some w -> w | None -> pattern in
  (* Try EC env pretty info where possible; fallback to outline *)
  let env_info =
    match id_of_pos st pos with
    | None -> None
    | Some id ->
      begin match ExecutionManager.get_easycrypt_state st.execution_state id with
      | None -> None
      | Some scope ->
        let env = EcLib.EcScope.env scope in
        let ppe = EcLib.EcPrinting.PPEnv.ofenv env in
        let pp s f x = try Some (Format.asprintf "%s: %a" s f x) with _ -> None in
        (* Only variables are safe with simple inputs; others require paths *)
        match EcLib.EcEnv.Var.lookup_local_opt word env with
        | Some _ -> Some (Printf.sprintf "local variable: %s" word)
        | None ->
          begin match EcLib.EcEnv.Var.lookup_progvar_opt ([], word) env with
          | Some (`Var pv, _ty) -> pp "program variable" (EcLib.EcPrinting.pp_pv ppe) pv
          | Some (`Proj (pv, _arg), _ty) -> pp "program variable" (EcLib.EcPrinting.pp_pv ppe) pv
          | None -> None
          end
      end
  in
  match env_info with
  | Some s -> Ok s
  | None ->
    let target = String.lowercase_ascii word in
    let outline = Document.outline st.document in
    let found = List.find_opt (fun (e:Document.outline_element) -> String.equal (String.lowercase_ascii e.name) target) outline in
    (match found with
    | Some e -> Ok e.statement
    | None -> Ok ("Print: " ^ word))

(* EasyCrypt stub - Coq warning system not needed *)
let warn_nested_proofs_opt () = ()

let () = (* EasyCrypt - no option system needed *) ()

(* AST/env and symbol index plumbing for LSP callers *)
let get_env_of_sentence st sid = ExecutionManager.get_env_of_sentence st.execution_state sid
let get_ast_of_sentence st sid = ExecutionManager.get_ast_of_sentence st.execution_state sid
let lookup_symbol_def st name = ExecutionManager.lookup_symbol_def st.execution_state name

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
  let cancel st = Option.iter Sel.Event.cancel st.cancel_handle

end

(* Interactive proving commands - using existing functions and implementing missing ones *)

let interpret_to_next st =
  (* Find next sentence and execute to it *)
  let current_id = Internal.observe_id st in
  match current_id with
  | Some current_id ->
    (* Find next sentence after current *)
    let sentences = Document.sentences st.document in
    let rec find_next = function
      | [] -> None
      | s :: rest when s.Document.id = current_id ->
        (match rest with
         | next :: _ -> Some next.Document.id
         | [] -> None)
      | _ :: rest -> find_next rest
    in
    (match find_next sentences with
     | Some next_id ->
        let before = get_proof st (Some current_id) in
        let st', events = observe ~background:false st next_id ~should_block_on_error:true in
        let after = get_proof st' (Some next_id) in
        let nav_history =
          match before, after with
          | Some b, Some a ->
            let step : Protocol.ProofState.proof_step_info = {
              step_id = (List.length st.nav_history) + 1;
              command = "stepForward";
              position = RawDocument.position_of_loc (Document.raw_document st'.document) (RawDocument.loc_of_position (Document.raw_document st'.document) (RawDocument.position_of_loc (Document.raw_document st'.document) 0));
              timestamp = Unix.gettimeofday ();
              goals_before = b.goals;
              goals_after = a.goals;
            } in
            st.nav_history @ [step]
          | _ -> st.nav_history
        in
        { st' with nav_history }, events
     | None -> st, [])
  | None ->
    (* Start from first sentence *)
    match Document.sentences st.document with
    | first :: _ ->
      let before = get_proof st None in
      let st', events = observe ~background:false st first.Document.id ~should_block_on_error:true in
      let after = get_proof st' (Some first.Document.id) in
      let nav_history =
        match before, after with
        | Some b, Some a ->
          let step : Protocol.ProofState.proof_step_info = {
            step_id = 1;
            command = "stepForward";
            position = RawDocument.position_of_loc (Document.raw_document st'.document) 0;
            timestamp = Unix.gettimeofday ();
            goals_before = b.goals;
            goals_after = a.goals;
          } in [step]
        | _ -> [] in
      { st' with nav_history }, events
    | [] -> st, []

(* interpret_to_previous already exists in the file - just expose it *)

(* interpret_to_position already exists - just expose it via the existing one *)

let interpret_to_end st =
  (* Execute to the last sentence in the document *)
  let sentences = Document.sentences st.document in
  match List.rev sentences with
  | last :: _ -> 
    log (fun () -> Printf.sprintf "Executing to end of document (sentence %d)" last.Document.id);
    observe ~background:false st last.Document.id ~should_block_on_error:true
  | [] -> 
    log (fun () -> "No sentences to execute");
    st, []
