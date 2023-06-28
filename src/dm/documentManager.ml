(**************************************************************************)
(*                                                                        *)
(*                                 VSCoq                                  *)
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

open Types
open Lsp.LspData

let Log log = Log.mk_log "documentManager"

type state = {
  uri : Uri.t;
  init_vs : unit;
  (* opts : Coqargs.injection_command list; *)
  document : Document.document;
  execution_state : ExecutionManager.state;
  observe_id : Types.sentence_id option; (* TODO materialize observed loc and line-by-line execution status *)
}

type event =
  | Execute of { (* we split the computation to help interruptibility *)
      id : Types.sentence_id; (* sentence of interest *)
      vst_for_next_todo : Vernacstate.t; (* the state to be used for the next
        todo, it is not necessarily the state of the last sentence, since it
        may have failed and this is a surrogate used for error resiliancy *)
      todo : ExecutionManager.prepared_task list;
      started : float; (* time *)
    }
  | ExecutionManagerEvent of ExecutionManager.event
let pp_event fmt = function
  | Execute { id; todo; started; _ } ->
      let time = Unix.gettimeofday () -. started in 
      Stdlib.Format.fprintf fmt "ExecuteToLoc %d (%d tasks left, started %2.3f ago)" (Stateid.to_int id) (List.length todo) time
  | ExecutionManagerEvent _ -> Stdlib.Format.fprintf fmt "ExecutionManagerEvent"


type events = event Sel.event list
let inject_em_event x = Sel.map (fun e -> ExecutionManagerEvent e) x
let inject_em_events events = List.map inject_em_event events

type exec_overview = {
  parsed : Range.t list;
  checked : Range.t list;
  checked_by_delegate : Range.t list;
  legacy_highlight : Range.t list;
}

let merge_ranges doc (r1,l) r2 =
  let loc1 = RawDocument.loc_of_position doc r1.Range.end_ in
  let loc2 = RawDocument.loc_of_position doc r2.Range.start in
  if RawDocument.only_whitespace_between doc (loc1+1) (loc2-1) then
    Range.{ start = r1.Range.start; end_ = r2.Range.end_ }, l
  else
    r2, r1 :: l

let compress_ranges doc = function
  | [] -> []
  | range :: tl ->
    let r, l = List.fold_left (merge_ranges doc) (range,[]) tl in
    r :: l

let executed_ranges doc execution_state loc =
  let ranges_of l =
    compress_ranges (Document.raw_document doc) @@
    List.sort (fun { Range.start = s1 } { Range.start = s2 } -> compare s1 s2) @@
    List.map (Document.range_of_id doc) l in
  let ids_before_loc = List.map (fun s -> s.Document.id) @@ Document.sentences_before doc loc in
  let ids = List.map (fun s -> s.Document.id) @@ Document.sentences doc in
  let executed_ids = List.filter (ExecutionManager.is_executed execution_state) ids in
  let remotely_executed_ids = List.filter (ExecutionManager.is_remotely_executed execution_state) ids in
  let parsed_ids = List.filter (fun x -> not (List.mem x executed_ids || List.mem x remotely_executed_ids)) ids in
  let legacy_ids = List.filter (fun x -> ExecutionManager.is_executed execution_state x || ExecutionManager.is_remotely_executed execution_state x) ids_before_loc in
  log @@ Printf.sprintf "highlight: legacy: %s" (String.concat " " (List.map Stateid.to_string legacy_ids));
  log @@ Printf.sprintf "highlight: parsed: %s" (String.concat " " (List.map Stateid.to_string parsed_ids));
  log @@ Printf.sprintf "highlight: parsed + checked: %s" (String.concat " " (List.map Stateid.to_string executed_ids));
  log @@ Printf.sprintf "highlight: parsed + checked_by_delegate: %s" (String.concat " " (List.map Stateid.to_string remotely_executed_ids));
  { 
    parsed = ranges_of parsed_ids;
    checked = ranges_of executed_ids;
    checked_by_delegate = ranges_of remotely_executed_ids;
    legacy_highlight = ranges_of legacy_ids; 
  }

let executed_ranges st =
  let loc = match Option.bind st.observe_id (Document.get_sentence st.document) with
  | None -> 0
  | Some { stop } -> stop
  in
  executed_ranges st.document st.execution_state loc

let interpret_to ~stateful ~background state id : (state * event Sel.event list) =
  state, []

let interpret_to_position ~stateful st pos =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  match Document.find_sentence_before st.document loc with
  | None -> (st, []) (* document is empty *)
  | Some { id } -> interpret_to ~stateful ~background:false st id

let interpret_to_previous st = st, []

let interpret_to_next st = st, []

let interpret_to_end st =
  match Document.get_last_sentence st.document with 
  | None -> (st, [])
  | Some {id} -> log ("interpret_to_end id = " ^ Stateid.to_string id); interpret_to ~stateful:true ~background:false st id

let hover st pos = 
  let pattern = RawDocument.word_at_position (Document.raw_document st.document) pos in
  Option.map (fun p -> Ok(p)) pattern

let make_diagnostic doc range oloc message severity =
  let range =
    match oloc with
    | None -> range
    | Some loc ->
      RawDocument.range_of_loc loc
  in
  Diagnostic.{ range; message; severity }

let diagnostics st =
  let parse_errors = Document.parse_errors st.document in
  let all_exec_errors = ExecutionManager.errors st.execution_state in
  let all_feedback = ExecutionManager.feedback st.execution_state in
  (* we are resilient to a state where invalidate was not called yet *)
  let exists (id,_) = Option.is_some (Document.get_sentence st.document id) in
  let exec_errors = all_exec_errors |> List.filter exists in
  let feedback = all_feedback |> List.filter exists in
  let mk_diag (id,(lvl,oloc,msg)) =
    make_diagnostic st.document (Document.range_of_id st.document id) oloc msg lvl
  in
  let mk_error_diag (id,(oloc,msg)) = mk_diag (id,(Severity.Error ,oloc,msg)) in
  let mk_parsing_error_diag Document.{ msg = {pl_loc; pl_desc}; start; stop } =
    let doc = Document.raw_document st.document in
    let severity = Severity.Error in
    let start = RawDocument.position_of_loc doc start in
    let end_ = RawDocument.position_of_loc doc stop in
    let range = Range.{ start; end_ } in
    make_diagnostic st.document range (Some pl_loc) pl_desc severity
  in
  List.map mk_parsing_error_diag parse_errors @
    List.map mk_error_diag exec_errors @
    List.map mk_diag feedback

let retract state loc =
  match Option.bind state.observe_id (Document.get_sentence state.document) with
  | None -> state
  | Some { stop } ->
    if loc < stop then
      let observe_id = Option.map (fun s -> s.Document.id) @@ Document.find_sentence_before state.document loc in
      { state with observe_id }
    else state

let apply_text_edits state edits =
  let document, loc = Document.apply_text_edits state.document edits in
  let state = { state with document } in
  retract state loc

let validate_document state =
  let invalid_ids, document = Document.validate_document state.document in
  let execution_state =
    List.fold_left (fun st id ->
      ExecutionManager.invalidate (Document.schedule state.document) id st
      ) state.execution_state (StateidSet.elements invalid_ids) in
  { state with document; execution_state }

let handle_event ev st =
  match ev with
  | Execute { id; todo = []; started } -> (* the vst_for_next_todo is also in st.execution_state *)
    let time = Unix.gettimeofday () -. started in 
    log (Printf.sprintf "ExecuteToLoc %d ends after %2.3f" (Stateid.to_int id) time);
    (* We update the state to trigger a publication of diagnostics *)
    (Some st, [])
  | Execute { id; vst_for_next_todo; started; todo = task :: todo } ->
    (*log "Execute (more tasks)";*)
    let (execution_state,vst_for_next_todo,events,_interrupted) =
      ExecutionManager.execute st.execution_state (vst_for_next_todo, [], false) task in
    (* We do not update the state here because we may have received feedback while
       executing *)
    (Some {st with execution_state}, inject_em_events events @ [Sel.now (Execute {id; vst_for_next_todo; todo; started })])
  | ExecutionManagerEvent ev ->
    let execution_state_update, events = ExecutionManager.handle_event ev st.execution_state in
    (Option.map (fun execution_state -> {st with execution_state}) execution_state_update, inject_em_events events)

module Internal = struct

  let document st =
    st.document

  let execution_state st =
    st.execution_state

  let observe_id st =
    st.observe_id

  let string_of_state st =
    let sentences = Document.sentences_sorted_by_loc st.document in
    let string_of_state id =
      if ExecutionManager.is_executed st.execution_state id then "(executed)"
      else if ExecutionManager.is_remotely_executed st.execution_state id then "(executed in worker)"
      else "(not executed)"
    in
    let string_of_sentence sentence =
      Document.Internal.string_of_sentence sentence ^ " " ^ string_of_state sentence.id
    in
    String.concat "\n" @@ List.map string_of_sentence sentences

end
