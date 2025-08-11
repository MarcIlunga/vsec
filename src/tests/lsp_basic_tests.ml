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

(** Basic LSP Data Structure Tests *)

open Base
open Lsp
open LspData

[@@@warning "-27"]

(** Basic Data Structure Tests *)

let%test_unit "position_creation_and_comparison" =
  let pos1 = Position.{ line = 5; character = 10 } in
  let pos2 = Position.{ line = 5; character = 20 } in
  let pos3 = Position.{ line = 6; character = 5 } in
  
  (* Test position comparison *)
  [%test_eq: int] (Position.compare pos1 pos1) 0;
  assert (Position.compare pos1 pos2 < 0);
  assert (Position.compare pos1 pos3 < 0)

let%test_unit "range_creation_and_serialization" =
  let start_pos = Position.{ line = 5; character = 10 } in
  let end_pos = Position.{ line = 5; character = 20 } in
  let range = Range.{ start = start_pos; end_ = end_pos } in
  
  (* Test JSON serialization roundtrip *)
  let json = Range.yojson_of_t range in
  let parsed = Range.t_of_yojson json in
  [%test_eq: Position.t] parsed.start start_pos;
  [%test_eq: Position.t] parsed.end_ end_pos

let%test_unit "uri_creation_and_path_extraction" =
  let original_path = "/home/user/project/test.ec" in
  let uri = Uri.make ~scheme:"file" ~path:original_path () in
  let extracted_path = Uri.path uri in
  [%test_eq: string] original_path extracted_path;
  
  (* Test URI serialization *)
  let json = Uri.yojson_of_t uri in
  let parsed = Uri.t_of_yojson json in
  [%test_eq: string] (Uri.path parsed) original_path

(** Server Capabilities Tests *)

let%test_unit "server_capabilities_basic" =
  let capabilities = ServerCapabilities.{
    textDocumentSync = ServerCapabilities.Incremental;
    completionProvider = ServerCapabilities.{
      triggerCharacters = Some ["."; ":"];
      allCommitCharacters = Some [" "; "."];
      resolveProvider = Some false;
      completionItem = Some ServerCapabilities.{ labelDetailsSupport = Some true };
    };
    hoverProvider = true;
    semanticTokensProvider = None;
  } in
  
  (* Test that capabilities can be created and serialized *)
  let json = ServerCapabilities.yojson_of_t capabilities in
  let parsed = ServerCapabilities.t_of_yojson json in
  [%test_eq: bool] parsed.hoverProvider capabilities.hoverProvider

let%test_unit "semantic_tokens_server_capability" =
  let legend = ServerCapabilities.{
    tokenTypes = ["keyword"; "tactic"; "module"; "theory"; "operator"; "predicate"];
    tokenModifiers = ["definition"; "readonly"; "static"];
  } in
  let semantic_options = ServerCapabilities.{
    legend = legend;
    range = Some true;
    full = Some true;
  } in
  let capabilities = ServerCapabilities.{
    textDocumentSync = ServerCapabilities.Incremental;
    completionProvider = ServerCapabilities.{
      triggerCharacters = Some [];
      allCommitCharacters = None;
      resolveProvider = Some false;
      completionItem = None;
    };
    hoverProvider = false;
    semanticTokensProvider = Some semantic_options;
  } in
  
  (* Test semantic tokens capability serialization *)
  let json = ServerCapabilities.yojson_of_t capabilities in
  let parsed = ServerCapabilities.t_of_yojson json in
  match parsed.semanticTokensProvider with
  | Some options -> 
    [%test_eq: string list] options.legend.tokenTypes legend.tokenTypes;
    [%test_eq: string list] options.legend.tokenModifiers legend.tokenModifiers
  | None -> failwith "Semantic tokens capability not preserved"

(** Hover Tests *)

let%test_unit "hover_response_creation" =
  let hover_text = "**Definition**: `x : bool`\n\nA boolean variable defined as `true`" in
  let hover = Hover.{ contents = hover_text } in
  
  (* Test hover serialization *)
  let json = Hover.yojson_of_t hover in
  let parsed = Hover.t_of_yojson json in
  [%test_eq: string] parsed.contents hover_text

(** Settings Tests *)

let%test_unit "delegation_mode_serialization" =
  let modes = [
    Settings.DelegationMode.None;
    Settings.DelegationMode.Skip;
    Settings.DelegationMode.Delegate;
  ] in
  
  List.iter modes ~f:(fun mode ->
    let json = Settings.DelegationMode.yojson_of_t mode in
    let _parsed = Settings.DelegationMode.t_of_yojson json in
    (* Successfully parsed without error *)
    ()
  )

let%test_unit "proof_mode_serialization" =
  let modes = [
    Settings.Mode.Manual;
    Settings.Mode.Continuous;
  ] in
  
  List.iter modes ~f:(fun mode ->
    let json = Settings.Mode.yojson_of_t mode in
    let _parsed = Settings.Mode.t_of_yojson json in
    (* Successfully parsed without error *)
    ()
  )

let%test_unit "proof_settings_complete" =
  let proof_settings = Settings.Proof.{
    delegation = Settings.DelegationMode.Skip;
    workers = Some 4;
    mode = Settings.Mode.Continuous;
  } in
  
  let settings = Settings.{ proof = proof_settings } in
  
  (* Test settings serialization *)
  let json = Settings.yojson_of_t settings in
  let _parsed = Settings.t_of_yojson json in
  (* Successfully parsed without error *)
  ()

(** Error Handling Tests *)

let%test_unit "invalid_position_values" =
  (* Test that negative line/character values work (LSP allows them) *)
  let pos = Position.{ line = -1; character = 0 } in
  let json = Position.yojson_of_t pos in
  let parsed = Position.t_of_yojson json in
  [%test_eq: int] parsed.line (-1)

let%test_unit "uri_edge_cases" =
  (* Test URI with special characters *)
  let special_path = "/path/with spaces/and%20encoding.ec" in
  let uri = Uri.of_fname special_path in
  let json = Uri.yojson_of_t uri in
  let parsed = Uri.t_of_yojson json in
  (* Note: Uri handling may normalize the path *)
  assert (String.contains (Uri.path parsed) ' ')

(** Integration Tests *)

let%test_unit "document_coordinates_integration" =
  (* Test typical document navigation scenario *)
  let document_uri = Uri.of_fname "/tmp/test.ec" in
  let start_pos = Position.{ line = 0; character = 0 } in
  let end_pos = Position.{ line = 0; character = 21 } in
  let range = Range.{ start = start_pos; end_ = end_pos } in
  
  (* Simulate definition found at this range *)
  let definition_location = (document_uri, range) in
  
  (* Test that all components work together *)
  match definition_location with
  | (uri, r) when String.equal (Uri.path uri) "/tmp/test.ec" && r.start.line = 0 -> ()
  | _ -> failwith "Document coordinate integration test failed"