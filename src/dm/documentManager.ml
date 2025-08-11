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
    let lvl = DiagnosticSeverity.of_feedback_level lvl in
    make_diagnostic st.document (Document.range_of_id st.document id) oloc msg (DiagnosticSeverity.to_lsp lvl) code

let mk_error_diag st (id,(oloc,msg,qf)) = (* mk_diag st (id,(Feedback.Error,oloc, msg)) *)
  let code = 
    (* EasyCrypt doesn't use Coq's Quickfix system *)
    match qf with
    | None -> None
    | Some _qf -> None (* Simplified for EasyCrypt - no quickfix support *)
  in
  let lvl = DiagnosticSeverity.of_feedback_level () in (* Simplified for EasyCrypt *)
  make_diagnostic st.document (Document.range_of_id st.document id) oloc msg (DiagnosticSeverity.to_lsp lvl) code


let mk_parsing_error_diag st Document.{ msg = (oloc,msg); start; stop; str } =
  let doc = Document.raw_document st.document in
  let severity = DiagnosticSeverity.Error in
  let start = RawDocument.position_of_loc doc start in
  let end_ = RawDocument.position_of_loc doc stop in
  let range = Range.{ start; end_ } in
  let code = None in (* EasyCrypt doesn't use quickfix *)
  make_diagnostic st.document range None msg (DiagnosticSeverity.to_lsp severity) code

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
        {state with execution_state; cancel_handle}, [event]
    | None ->
      match error_id with
      | None ->
        {state with execution_state}, []
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

let interpret_to st id check_mode =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

let interpret_to_next_position st pos =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

let interpret_to_position st pos =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

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
  (* EasyCrypt stub - Vernacstate module not implemented yet *)
  st, []

let interpret_to_next st =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

let interpret_to_end st =
  (* EasyCrypt stub - Settings module not implemented yet *)
  st, []

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
  let state = { uri; opts; init_vs; document; execution_state; observe_id=Top; cancel_handle = None; document_state = Parsing } in
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
  (* EasyCrypt stub - ProofState module not implemented yet *)
  None

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
  (* EasyCrypt stub - Settings module and complex event handling not implemented yet *)
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
