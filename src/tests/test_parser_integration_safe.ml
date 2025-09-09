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

(* TODO: Add more tests step by step:
   - Test parse_more when API signature is clarified
   - Test sentence parsing when Document.Internal API is stable
   - Test error handling when error format is consistent
*)
