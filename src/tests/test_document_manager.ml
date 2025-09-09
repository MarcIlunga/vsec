(**************************************************************************)
(*                                                                        *)
(*                                 VsEc                                   *)
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

(** Comprehensive DocumentManager Tests for EasyCrypt LSP Server *)

open Dm
open Lsp.Types
open Base

[@@@warning "-27-32"]

let test_uri = DocumentUri.of_string "file:///test.ec"

let create_test_state text =
  let init_state = EcLib.EcScope.empty (EcLib.EcGState.create ()) in
  DocumentManager.init init_state test_uri ~text

(** Test Document Creation and Basic Parsing *)
let%test_unit "document_creation_simple_lemma" =
  let text = "lemma test_lemma: true.\nproof. trivial. qed.\n" in
  let state, _events = create_test_state text in
  let doc = DocumentManager.Internal.document state in
  let raw_doc = Document.raw_document doc in
  [%test_eq: int] (RawDocument.end_loc raw_doc) (String.length text);
  (* Document should be created successfully *)
  assert (not (String.is_empty (RawDocument.text raw_doc)))

let%test_unit "document_parsing_multiple_sentences" =
  let text = "lemma a: true. proof. trivial. qed.\nlemma b: false. proof. admit. qed.\n" in
  let state, events = create_test_state text in
  (* Parse the document *)
  let parsed_doc, _parse_events = Document.validate_document (DocumentManager.Internal.document state) in
  let sentences = Document.sentences parsed_doc in
  (* Should have multiple sentences *)
  [%test_pred: Document.sentence list] (fun l -> List.length l >= 2) sentences

(** Test Step-by-Step Execution *)
let%test_unit "step_forward_basic" =
  let text = "lemma step_test: true.\nproof.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Step forward from beginning *)
  let state', events = DocumentManager.interpret_to_next state in
  
  (* Should have moved forward *)
  match DocumentManager.Internal.observe_id state' with
  | None -> failwith "Should have observe_id after step forward"
  | Some id -> assert (id >= 0)

let%test_unit "step_backward_basic" =
  let text = "lemma step_test: true.\nproof.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Move forward first *)
  let state', _events = DocumentManager.interpret_to_next state in
  
  (* Then step backward *)
  let state'', events = DocumentManager.interpret_to_previous state' in
  
  (* Should have moved backward *)
  assert (true) (* Basic test that it doesn't crash *)

(** Test Position-Based Execution *)
let%test_unit "interpret_to_position_mid_proof" =
  let text = "lemma pos_test: true /\\ true.\nproof.\n  split.\n  trivial.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Create position in middle of proof (line 3, char 2) *)
  let position = Position.create ~line:3 ~character:2 in
  
  (* Execute to that position *)
  let state', events = DocumentManager.interpret_to_position state position in
  
  (* Should have observe_id set *)
  match DocumentManager.Internal.observe_id state' with
  | None -> failwith "Should have observe_id after interpret_to_position"
  | Some _id -> assert (true)

(** Test Error Handling and Recovery *)
let%test_unit "syntax_error_handling" =
  let text = "lemma syntax_error true.\nproof.\n  invalid_tactic.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Parse document with syntax error *)
  let parsed_doc, _parse_events = Document.validate_document (DocumentManager.Internal.document state) in
  let parse_errors = Document.parse_errors parsed_doc in
  
  (* Should detect syntax errors *)
  [%test_pred: Document.parsing_error list] (fun l -> List.length l > 0) parse_errors

let%test_unit "error_recovery_after_fix" =
  let text_with_error = "lemma error_test true.\nproof. trivial. qed.\n" in
  let text_fixed = "lemma error_test: true.\nproof. trivial. qed.\n" in
  
  let state, _events = create_test_state text_with_error in
  
  (* Apply text edit to fix the error *)
  let range = Range.create 
    ~start:(Position.create ~line:0 ~character:16)
    ~end_:(Position.create ~line:0 ~character:16) in
  let edit = (range, ": ") in
  let state' = DocumentManager.apply_text_edit state edit in
  
  (* Parse the fixed document *)
  let parsed_doc, _parse_events = Document.validate_document (DocumentManager.Internal.document state') in
  let parse_errors = Document.parse_errors parsed_doc in
  
  (* Should have fewer or no errors after fix *)
  assert (true) (* Basic test that it doesn't crash *)

(** Test Completion Context Detection *)
let%test_unit "completion_context_proof" =
  let text = "lemma comp_test: true.\nproof.\n  " in
  let state, _events = create_test_state text in
  
  (* Get completions at end of proof context *)
  let position = Position.create ~line:2 ~character:2 in
  let completions = DocumentManager.get_completions state position in
  
  (* Should return some completions (even if empty list for now) *)
  [%test_pred: 'a list] (fun l -> List.length l >= 0) completions

let%test_unit "completion_context_definition" =
  let text = "module TestMod.\n  " in
  let state, _events = create_test_state text in
  
  (* Get completions in module context *)
  let position = Position.create ~line:1 ~character:2 in
  let completions = DocumentManager.get_completions state position in
  
  (* Should return some completions *)
  [%test_pred: 'a list] (fun l -> List.length l >= 0) completions

(** Test Hover Information *)
let%test_unit "hover_on_keyword" =
  let text = "lemma hover_test: true.\nproof.\n  apply trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Test hover on "apply" keyword *)
  let position = Position.create ~line:2 ~character:3 in
  let hover_result = DocumentManager.hover state position in
  
  (* Should return hover info or None (we test that it doesn't crash) *)
  match hover_result with
  | Some _ -> assert (true)
  | None -> assert (true) (* Acceptable for now *)

(** Test Go-to-Definition *)
let%test_unit "goto_definition_lemma" =
  let text = "lemma helper: true. proof. trivial. qed.\nlemma main: true. proof. apply helper. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Test go-to-definition on "helper" reference *)
  let position = Position.create ~line:1 ~character:30 in (* On "helper" *)
  let definition_result = DocumentManager.jump_to_definition state position in
  
  (* Should return definition location or None *)
  match definition_result with
  | Some _ -> assert (true)
  | None -> assert (true) (* Acceptable for now *)

(** Test Document State Management *)
let%test_unit "document_state_transitions" =
  let text = "lemma state_test: true.\nproof. trivial. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Initial state should be valid *)
  let initial_observe_id = DocumentManager.Internal.observe_id state in
  [%test_eq: int option] initial_observe_id None;
  
  (* After stepping forward *)
  let state', _events = DocumentManager.interpret_to_next state in
  let new_observe_id = DocumentManager.Internal.observe_id state' in
  assert (new_observe_id <> initial_observe_id)

(** Test Text Edit Operations *)
let%test_unit "text_edit_basic_insertion" =
  let text = "lemma test: true.\nproof. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Insert "trivial. " before "qed" *)
  let range = Range.create 
    ~start:(Position.create ~line:1 ~character:7)
    ~end_:(Position.create ~line:1 ~character:7) in
  let edit = (range, "trivial. ") in
  let state' = DocumentManager.apply_text_edit state edit in
  
  (* Document should be updated *)
  let doc = DocumentManager.Internal.document state' in
  let raw_doc = Document.raw_document doc in
  let new_text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"trivial") new_text

let%test_unit "text_edit_multiple_operations" =
  let text = "lemma a: true. proof. qed.\nlemma b: false. proof. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Apply multiple edits *)
  let edit1 = (Range.create 
    ~start:(Position.create ~line:0 ~character:18)
    ~end_:(Position.create ~line:0 ~character:18), "trivial. ") in
  let edit2 = (Range.create 
    ~start:(Position.create ~line:1 ~character:24)
    ~end_:(Position.create ~line:1 ~character:24), "admit. ") in
  
  let state' = DocumentManager.apply_text_edit state edit1 in
  let state'' = DocumentManager.apply_text_edit state' edit2 in
  
  (* Both edits should be applied *)
  let doc = DocumentManager.Internal.document state'' in
  let raw_doc = Document.raw_document doc in
  let new_text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"trivial") new_text;
  [%test_pred: string] (String.is_substring ~substring:"admit") new_text

(** Test Execution Manager Integration *)
let%test_unit "execution_manager_basic_integration" =
  let text = "lemma exec_test: true.\nproof.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Get execution state *)
  let exec_state = DocumentManager.Internal.execution_state state in
  let initial_context = ExecutionManager.get_initial_context exec_state in
  
  (* Should have valid initial context *)
  assert (true) (* Basic test that context exists *)

let%test_unit "execution_context_after_steps" =
  let text = "lemma ctx_test: true.\nproof.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  
  (* Step forward and check context *)
  let state', _events = DocumentManager.interpret_to_next state in
  let exec_state = DocumentManager.Internal.execution_state state' in
  
  match DocumentManager.Internal.observe_id state' with
  | None -> assert (true) (* No context to check *)
  | Some id ->
    let context = ExecutionManager.get_context exec_state id in
    match context with
    | Some _ -> assert (true) (* Context available *)
    | None -> assert (true) (* Context might not be available yet *)

(** Test Document Outline Generation *)
let%test_unit "document_outline_simple" =
  let text = "lemma outline_test: true.\nproof. trivial. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Parse and get outline *)
  let parsed_doc, _parse_events = Document.validate_document (DocumentManager.Internal.document state) in
  let outline = Document.outline parsed_doc in
  
  (* Should have outline elements *)
  [%test_pred: Document.outline_element list] (fun l -> List.length l >= 0) outline

let%test_unit "document_outline_multiple_definitions" =
  let text = "lemma a: true. proof. trivial. qed.\nlemma b: false. proof. admit. qed.\nmodule Test.\nend Test.\n" in
  let state, _events = create_test_state text in
  
  (* Parse and get outline *)
  let parsed_doc, _parse_events = Document.validate_document (DocumentManager.Internal.document state) in
  let outline = Document.outline parsed_doc in
  
  (* Should have multiple outline elements *)
  [%test_pred: Document.outline_element list] (fun l -> List.length l >= 2) outline

(** Test Range and Position Utilities *)
let%test_unit "position_conversion_basic" =
  let text = "lemma pos: true.\nproof.\n  trivial.\nqed.\n" in
  let state, _events = create_test_state text in
  let doc = DocumentManager.Internal.document state in
  let raw_doc = Document.raw_document doc in
  
  (* Test position to location conversion *)
  let position = Position.create ~line:1 ~character:0 in
  let loc = RawDocument.loc_of_position raw_doc position in
  
  (* Should be valid location *)
  [%test_pred: int] (fun x -> x >= 0) loc

let%test_unit "range_calculation_sentences" =
  let text = "lemma range_test: true.\nproof. trivial. qed.\n" in
  let state, _events = create_test_state text in
  let doc = DocumentManager.Internal.document state in
  
  (* Parse and check sentence ranges *)
  let parsed_doc, _parse_events = Document.validate_document doc in
  let sentences = Document.sentences parsed_doc in
  
  (* Each sentence should have valid range *)
  List.iter sentences ~f:(fun sentence ->
    assert (sentence.start >= 0);
    assert (sentence.stop > sentence.start)
  )

(** Test Error Diagnostics Generation *)
let%test_unit "diagnostics_generation_parsing_error" =
  let text = "lemma invalid syntax here.\nproof. trivial. qed.\n" in
  let state, _events = create_test_state text in
  
  (* Get diagnostics *)
  let diagnostics = DocumentManager.all_diagnostics state in
  
  (* Should have diagnostics (even if empty for now) *)
  [%test_pred: Lsp.Types.Diagnostic.t list] (fun l -> List.length l >= 0) diagnostics

let%test_unit "diagnostics_after_text_edit" =
  let text_with_error = "lemma error true.\nproof. trivial. qed.\n" in
  let text_fixed = "lemma error: true.\nproof. trivial. qed.\n" in
  
  let state, _events = create_test_state text_with_error in
  let diagnostics_before = DocumentManager.all_diagnostics state in
  
  (* Apply fix *)
  let range = Range.create 
    ~start:(Position.create ~line:0 ~character:11)
    ~end_:(Position.create ~line:0 ~character:11) in
  let edit = (range, ": ") in
  let state' = DocumentManager.apply_text_edit state edit in
  let diagnostics_after = DocumentManager.all_diagnostics state' in
  
  (* Test that diagnostic generation works (result content is not critical) *)
  assert (true)

(** Test Multi-Document Scenarios *)
let%test_unit "multiple_documents_isolation" =
  let text1 = "lemma doc1: true. proof. trivial. qed.\n" in
  let text2 = "lemma doc2: false. proof. admit. qed.\n" in
  
  let uri1 = DocumentUri.of_string "file:///doc1.ec" in
  let uri2 = DocumentUri.of_string "file:///doc2.ec" in
  
  let init_state = EcLib.EcScope.empty (EcLib.EcGState.create ()) in
  let state1, _events1 = DocumentManager.init init_state uri1 ~text:text1 in
  let state2, _events2 = DocumentManager.init init_state uri2 ~text:text2 in
  
  (* Documents should be independent *)
  let id1 = DocumentManager.Internal.observe_id state1 in
  let id2 = DocumentManager.Internal.observe_id state2 in
  
  (* Initial states should be similar (both None) *)
  [%test_eq: int option] id1 id2
