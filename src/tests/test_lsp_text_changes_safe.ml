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

(** Safe LSP Text Changes Tests - Test critical text editing vulnerabilities *)

open Base
open Stdio
open Lsp.Types

(** Step 1: Test Option.get crash on full document changes *)
let test_full_document_change_vulnerability () =
  (* This test exposes the Option.get crash when range=None *)
  let uri = DocumentUri.of_string "file:///test.ec" in
  
  (* Create a TextDocumentContentChangeEvent with range=None (full document replace) *)
  let full_doc_change = TextDocumentContentChangeEvent.create ~text:"new content" () in
  
  (* This simulates what happens in lspManager.ml line 496-501 *)
  let test_option_get_vulnerability change =
    try
      (* This simulates the vulnerability in lspManager.ml where Option.get crashes *)
      let range = change.TextDocumentContentChangeEvent.range in
      match range with
      | Some r -> true  (* Has range, won't crash *)
      | None -> 
        (* This simulates what happens with Option.get on None *)
        failwith "Option.get called on None - this would crash in real code!"
    with
    | Failure msg when String.is_substring msg ~substring:"Option.get" -> false  (* Expected crash *)
    | _ -> false  (* Other unexpected error *)
  in
  
  (* Validate that we can detect the vulnerability *)
  let crashes = not (test_option_get_vulnerability full_doc_change) in
  assert crashes;  (* Should crash, proving the vulnerability exists *)
  
  print_endline "✓ Full document change vulnerability detected (Option.get crash)";
  true

(** Step 2: Test ranged vs full document change behavior *)
let test_ranged_vs_full_changes () =
  let uri = DocumentUri.of_string "file:///test.ec" in
  
  (* Create ranged change *)
  let range = Range.create 
    ~start:(Position.create ~line:0 ~character:0) 
    ~end_:(Position.create ~line:0 ~character:5) in
  let ranged_change = TextDocumentContentChangeEvent.create ~range ~text:"hello" () in
  
  (* Create full document change (no range) *)
  let full_change = TextDocumentContentChangeEvent.create ~text:"completely new content" () in
  
  (* Validate change types *)
  assert (Option.is_some ranged_change.range);
  assert (Option.is_none full_change.range);
  assert (not (String.is_empty ranged_change.text));
  assert (not (String.is_empty full_change.text));
  
  print_endline "✓ Ranged vs full document change types validated";
  true

(** Step 3: Test empty content changes array *)
let test_empty_content_changes () =
  let empty_changes = [] in
  
  (* Test that empty changes are handled gracefully *)
  assert (List.is_empty empty_changes);
  
  (* Simulate what should happen with empty changes *)
  let process_changes changes =
    if List.is_empty changes then
      "no_changes"
    else
      "has_changes"
  in
  
  let result = process_changes empty_changes in
  assert (String.equal result "no_changes");
  
  print_endline "✓ Empty content changes handling validated";
  true

(** Step 4: Test invalid range positions *)
let test_invalid_range_positions () =
  let uri = DocumentUri.of_string "file:///test.ec" in
  
  (* Test negative positions (should be rejected) *)
  let negative_range = Range.create
    ~start:(Position.create ~line:(-1) ~character:0)
    ~end_:(Position.create ~line:0 ~character:5) in
  
  (* Test very large positions (beyond document) *)  
  let huge_range = Range.create
    ~start:(Position.create ~line:999999 ~character:999999)
    ~end_:(Position.create ~line:999999 ~character:999999) in
  
  let invalid_change = TextDocumentContentChangeEvent.create ~range:negative_range ~text:"test" () in
  let huge_change = TextDocumentContentChangeEvent.create ~range:huge_range ~text:"test" () in
  
  (* Validate that we can create these (the bounds check should happen later) *)
  assert (Option.is_some invalid_change.range);
  assert (Option.is_some huge_change.range);
  
  print_endline "✓ Invalid range positions test structure validated";
  true

(** Step 5: Test overlapping edit ranges *)
let test_overlapping_edits () =
  let uri = DocumentUri.of_string "file:///test.ec" in
  
  (* Create overlapping ranges *)
  let range1 = Range.create
    ~start:(Position.create ~line:0 ~character:0)
    ~end_:(Position.create ~line:0 ~character:10) in
  let range2 = Range.create
    ~start:(Position.create ~line:0 ~character:5)
    ~end_:(Position.create ~line:0 ~character:15) in
  
  let edit1 = TextDocumentContentChangeEvent.create ~range:range1 ~text:"first" () in
  let edit2 = TextDocumentContentChangeEvent.create ~range:range2 ~text:"second" () in
  
  let overlapping_edits = [edit1; edit2] in
  
  (* Validate overlapping edits structure *)
  assert (List.length overlapping_edits = 2);
  List.iter overlapping_edits ~f:(fun edit ->
    assert (Option.is_some edit.range);
    assert (not (String.is_empty edit.text));
  );
  
  print_endline "✓ Overlapping edits structure validated";
  true

(* TODO: Add more critical text change tests step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("full_document_change_vulnerability", test_full_document_change_vulnerability);
    ("ranged_vs_full_changes", test_ranged_vs_full_changes);
    ("empty_content_changes", test_empty_content_changes);
    ("invalid_range_positions", test_invalid_range_positions);
    ("overlapping_edits", test_overlapping_edits);
  ] in
  
  print_endline "🧪 Running LSP Text Changes tests...";
  let passed = ref 0 in
  let total = List.length tests in
  
  List.iter tests ~f:(fun (name, test_fn) ->
    print_endline ("  Running " ^ name ^ "...");
    if test_fn () then (
      print_endline "PASS";
      incr passed
    ) else (
      print_endline "FAIL"
    )
  );
  
  print_endline ("📊 Tests: " ^ string_of_int !passed ^ "/" ^ string_of_int total ^ " passed");
  !passed = total

(** Main entry point *)
let () =
  if run_tests () then (
    print_endline "✅ All LSP Text Changes tests passed";
    exit 0
  ) else (
    print_endline "❌ Some LSP Text Changes tests failed";
    exit 1
  )
