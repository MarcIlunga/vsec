(* Safe EasyCrypt parser integration tests *)
open Base
open Stdio
open Dm

(* TODO: Add parser integration tests incrementally as APIs stabilize *)

let%test_unit "basic_document_access" =
  (* Test that we can access basic document modules *)
  let text = "" in
  let _raw_doc = RawDocument.create text in
  print_endline "✓ Parser integration module access works"

let%test_unit "document_manager_with_text" =
  (* Test DocumentManager with actual EasyCrypt text *)
  let text = "theory Test. end Test." in
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  let uri = Lsp.Types.DocumentUri.of_string "file:///test.ec" in
  let _state, _events = DocumentManager.init scope uri ~text in
  print_endline "✓ DocumentManager with EasyCrypt text works"

(* TODO: Add more tests step by step:
   - Test parse_more when API signature is clarified
   - Test sentence parsing when Document.Internal API is stable
   - Test error handling when error format is consistent
*)
