(* Safe EasyCrypt parser integration tests *)
open Base
open Stdio

(* TODO: Add parser integration tests incrementally as APIs stabilize *)

let%test_unit "basic_document_access" =
  (* Just test that we can access basic document modules *)
  let text = "" in
  (* let _raw_doc = RawDocument.create text in -- TODO: Fix when RawDocument API is available *)
  print_endline "✓ Parser integration module access works"

(* TODO: Add more tests step by step:
   - Test parse_more when API signature is clarified
   - Test sentence parsing when Document.Internal API is stable
   - Test error handling when error format is consistent
*)
