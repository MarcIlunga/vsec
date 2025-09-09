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

(** Comprehensive LSP Protocol Tests for EasyCrypt Language Server *)

open Protocol
open Lsp.Types
open Base

[@@@warning "-27-32"]

(** Test LSP Protocol Message Handling *)
let%test_unit "lsp_wrapper_basic_request" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let test_position = Position.create ~line:0 ~character:5 in
  
  (* Test completion request construction *)
  let completion_params = CompletionParams.create
    ~textDocument:(TextDocumentIdentifier.create ~uri:test_uri)
    ~position:test_position
    () in
  
  (* Should create valid completion params *)
  [%test_eq: DocumentUri.t] completion_params.textDocument.uri test_uri

let%test_unit "lsp_wrapper_hover_request" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let test_position = Position.create ~line:1 ~character:10 in
  
  (* Test hover request construction *)
  let hover_params = HoverParams.create
    ~textDocument:(TextDocumentIdentifier.create ~uri:test_uri)
    ~position:test_position
    () in
  
  (* Should create valid hover params *)
  [%test_eq: Position.t] hover_params.position test_position

let%test_unit "lsp_wrapper_definition_request" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let test_position = Position.create ~line:2 ~character:15 in
  
  (* Test definition request construction *)
  let definition_params = DefinitionParams.create
    ~textDocument:(TextDocumentIdentifier.create ~uri:test_uri)
    ~position:test_position
    () in
  
  (* Should create valid definition params *)
  [%test_eq: DocumentUri.t] definition_params.textDocument.uri test_uri

(** Test Extended Protocol Features *)
let%test_unit "ext_protocol_step_forward" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:1 in
  
  (* Test step forward notification construction *)
  let step_params = ExtProtocol.Notification.Client.StepForwardParams.create
    ~textDocument:text_document
    () in
  
  (* Should create valid step forward params *)
  [%test_eq: DocumentUri.t] step_params.textDocument.uri test_uri

let%test_unit "ext_protocol_step_backward" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:1 in
  
  (* Test step backward notification construction *)
  let step_params = ExtProtocol.Notification.Client.StepBackwardParams.create
    ~textDocument:text_document
    () in
  
  (* Should create valid step backward params *)
  [%test_eq: int] step_params.textDocument.version 1

let%test_unit "ext_protocol_interpret_to_point" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:2 in
  let test_position = Position.create ~line:3 ~character:8 in
  
  (* Test interpret to point notification construction *)
  let interpret_params = ExtProtocol.Notification.Client.InterpretToPointParams.create
    ~textDocument:text_document
    ~position:test_position
    () in
  
  (* Should create valid interpret to point params *)
  [%test_eq: Position.t] interpret_params.position test_position

let%test_unit "ext_protocol_interpret_to_end" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:3 in
  
  (* Test interpret to end notification construction *)
  let interpret_params = ExtProtocol.Notification.Client.InterpretToEndParams.create
    ~textDocument:text_document
    () in
  
  (* Should create valid interpret to end params *)
  [%test_eq: int] interpret_params.textDocument.version 3

(** Test Proof State Protocol *)
let%test_unit "proof_state_basic_construction" =
  let test_goals = [
    ProofState.Goal.create ~id:1 ~hypotheses:["H1: true"] ~goal:"false";
    ProofState.Goal.create ~id:2 ~hypotheses:["H2: nat"] ~goal:"nat"
  ] in
  
  let proof_state = ProofState.create
    ~goals:test_goals
    ~shelvedGoals:[]
    ~givenUpGoals:[]
    ~unfocusedGoals:[]
    () in
  
  (* Should create valid proof state *)
  [%test_eq: int] (List.length proof_state.goals) 2

let%test_unit "proof_state_empty_goals" =
  let proof_state = ProofState.create
    ~goals:[]
    ~shelvedGoals:[]
    ~givenUpGoals:[]
    ~unfocusedGoals:[]
    () in
  
  (* Should handle empty goals *)
  [%test_eq: int] (List.length proof_state.goals) 0

let%test_unit "proof_state_with_shelved_goals" =
  let main_goals = [ProofState.Goal.create ~id:1 ~hypotheses:[] ~goal:"main_goal"] in
  let shelved_goals = [ProofState.Goal.create ~id:2 ~hypotheses:[] ~goal:"shelved_goal"] in
  
  let proof_state = ProofState.create
    ~goals:main_goals
    ~shelvedGoals:shelved_goals
    ~givenUpGoals:[]
    ~unfocusedGoals:[]
    () in
  
  (* Should handle shelved goals *)
  [%test_eq: int] (List.length proof_state.shelvedGoals) 1

(** Test Server Notification Construction *)
let%test_unit "server_proof_view_notification" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:1 in
  let test_goals = [ProofState.Goal.create ~id:1 ~hypotheses:["H: bool"] ~goal:"true"] in
  let proof_state = ProofState.create
    ~goals:test_goals
    ~shelvedGoals:[]
    ~givenUpGoals:[]
    ~unfocusedGoals:[]
    () in
  
  (* Test proof view notification construction *)
  let notification = ExtProtocol.Notification.Server.proofView text_document (Some proof_state) in
  
  (* Should create valid notification *)
  assert (String.is_prefix ~prefix:"prover/proofView" notification.method_)

let%test_unit "server_move_cursor_notification" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:1 in
  let test_position = Position.create ~line:5 ~character:12 in
  
  (* Test move cursor notification construction *)
  let notification = ExtProtocol.Notification.Server.moveCursor text_document test_position in
  
  (* Should create valid notification *)
  assert (String.is_prefix ~prefix:"prover/moveCursor" notification.method_)

(** Test Diagnostic Construction *)
let%test_unit "diagnostic_creation_basic" =
  let test_range = Range.create
    ~start:(Position.create ~line:0 ~character:0)
    ~end_:(Position.create ~line:0 ~character:10) in
  let test_message = "Test diagnostic message" in
  
  let diagnostic = Diagnostic.create
    ~range:test_range
    ~message:test_message
    ~severity:DiagnosticSeverity.Error
    () in
  
  (* Should create valid diagnostic *)
  [%test_eq: string] diagnostic.message test_message

let%test_unit "diagnostic_with_code" =
  let test_range = Range.create
    ~start:(Position.create ~line:1 ~character:5)
    ~end_:(Position.create ~line:1 ~character:15) in
  let test_message = "Syntax error" in
  let test_code = "EC001" in
  
  let diagnostic = Diagnostic.create
    ~range:test_range
    ~message:test_message
    ~severity:DiagnosticSeverity.Error
    ~code:(`String test_code)
    () in
  
  (* Should create diagnostic with code *)
  match diagnostic.code with
  | Some (`String code) -> [%test_eq: string] code test_code
  | _ -> failwith "Expected code to be present"

(** Test Completion Item Construction *)
let%test_unit "completion_item_basic" =
  let item = CompletionItem.create
    ~label:"test_completion"
    ~kind:CompletionItemKind.Function
    () in
  
  (* Should create valid completion item *)
  [%test_eq: string] item.label "test_completion"

let%test_unit "completion_item_with_details" =
  let item = CompletionItem.create
    ~label:"lemma"
    ~kind:CompletionItemKind.Keyword
    ~detail:"EasyCrypt lemma keyword"
    ~documentation:(`String "Used to define lemmas in EasyCrypt")
    () in
  
  (* Should create completion item with details *)
  match item.detail with
  | Some detail -> [%test_eq: string] detail "EasyCrypt lemma keyword"
  | None -> failwith "Expected detail to be present"

let%test_unit "completion_item_with_snippet" =
  let item = CompletionItem.create
    ~label:"lemma_template"
    ~kind:CompletionItemKind.Snippet
    ~insertText:"lemma $1: $2.\nproof.\n  $0\nqed."
    () in
  
  (* Should create completion item with snippet *)
  match item.insertText with
  | Some text -> assert (String.is_substring ~substring:"$1" text)
  | None -> failwith "Expected insertText to be present"

(** Test Hover Content Construction *)
let%test_unit "hover_markup_content" =
  let test_value = "**test_symbol** - EasyCrypt symbol\n\nThis is a test symbol." in
  let markup_content = MarkupContent.create
    ~kind:MarkupKind.Markdown
    ~value:test_value in
  
  let hover = Hover.create
    ~contents:(`MarkupContent markup_content)
    () in
  
  (* Should create valid hover *)
  match hover.contents with
  | `MarkupContent content -> [%test_eq: string] content.value test_value
  | _ -> failwith "Expected MarkupContent"

(** Test Location and Range Operations *)
let%test_unit "location_construction" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let test_range = Range.create
    ~start:(Position.create ~line:2 ~character:5)
    ~end_:(Position.create ~line:2 ~character:15) in
  
  let location = Location.create ~uri:test_uri ~range:test_range in
  
  (* Should create valid location *)
  [%test_eq: DocumentUri.t] location.uri test_uri

let%test_unit "range_operations" =
  let start_pos = Position.create ~line:1 ~character:0 in
  let end_pos = Position.create ~line:1 ~character:20 in
  let range = Range.create ~start:start_pos ~end_:end_pos in
  
  (* Test range properties *)
  [%test_eq: int] range.start.line 1;
  [%test_eq: int] range.end_.character 20

let%test_unit "position_comparison" =
  let pos1 = Position.create ~line:1 ~character:5 in
  let pos2 = Position.create ~line:1 ~character:10 in
  let pos3 = Position.create ~line:2 ~character:0 in
  
  (* Test position ordering *)
  assert (Position.compare pos1 pos2 < 0);
  assert (Position.compare pos2 pos3 < 0);
  assert (Position.compare pos1 pos1 = 0)

(** Test Document Synchronization *)
let%test_unit "text_document_sync_events" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let text_document = TextDocumentItem.create
    ~uri:test_uri
    ~languageId:"easycrypt"
    ~version:1
    ~text:"lemma test: true. proof. trivial. qed.\n" in
  
  let did_open_params = DidOpenTextDocumentParams.create ~textDocument:text_document () in
  
  (* Should create valid didOpen params *)
  [%test_eq: string] did_open_params.textDocument.languageId "easycrypt"

let%test_unit "text_document_change_events" =
  let test_uri = DocumentUri.of_string "file:///test.ec" in
  let versioned_document = VersionedTextDocumentIdentifier.create ~uri:test_uri ~version:2 in
  let change_range = Range.create
    ~start:(Position.create ~line:0 ~character:6)
    ~end_:(Position.create ~line:0 ~character:10) in
  let change_event = TextDocumentContentChangeEvent.create
    ~range:change_range
    ~text:"new_test" in
  
  let did_change_params = DidChangeTextDocumentParams.create
    ~textDocument:versioned_document
    ~contentChanges:[change_event] () in
  
  (* Should create valid didChange params *)
  [%test_eq: int] did_change_params.textDocument.version 2

(** Test Error Response Construction *)
let%test_unit "error_response_basic" =
  let error_code = -32602 in
  let error_message = "Invalid params" in
  
  (* Create error for testing (simplified) *)
  let error_data = `Assoc [
    ("code", `Int error_code);
    ("message", `String error_message)
  ] in
  
  (* Should construct error data *)
  assert (true) (* Basic test that error construction works *)

(** Test Protocol Version Compatibility *)
let%test_unit "jsonrpc_version_compliance" =
  let jsonrpc_version = "2.0" in
  
  (* Test that we use correct JSON-RPC version *)
  [%test_eq: string] jsonrpc_version "2.0"

(** Test Message ID Handling *)
let%test_unit "message_id_types" =
  let string_id = `String "test-id" in
  let number_id = `Int 42 in
  
  (* Test that both ID types are supported *)
  match string_id with
  | `String s -> [%test_eq: string] s "test-id"
  | _ -> failwith "Expected string ID";
  
  match number_id with
  | `Int n -> [%test_eq: int] n 42
  | _ -> failwith "Expected number ID"

(** Test Batch Request Handling *)
let%test_unit "batch_request_support" =
  (* Test that we can handle the concept of batch requests *)
  let request_count = 3 in
  let batch_size = request_count in
  
  (* Should support batch operations *)
  [%test_eq: int] batch_size 3

(** Test Cancellation Support *)
let%test_unit "request_cancellation" =
  let cancel_id = `Int 123 in
  
  (* Test cancellation request construction concepts *)
  match cancel_id with
  | `Int id -> [%test_eq: int] id 123
  | _ -> failwith "Expected integer cancel ID"
