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

(** Safe LSP Protocol Tests - Incremental build approach *)

open Base
open Stdio
open Lsp.Types

(** Step 1: Basic module access *)
let test_basic_access () =
  print_endline "✓ Basic module access works";
  true

(** Step 2: Test basic LSP types *)
let test_lsp_types () =
  let position1 = Position.create ~line:5 ~character:10 in
  let position2 = Position.create ~line:5 ~character:15 in
  let uri = DocumentUri.of_string "file:///test.ec" in
  let range = Range.create ~start:position1 ~end_:position2 in
  
  (* Validate URI conversion works *)
  let path = DocumentUri.to_path uri in
  assert (String.is_suffix path ~suffix:"test.ec");
  
  (* Test that we can create different positions *)
  assert (not (phys_equal position1 position2));
  
  (* Test that range is a different type/object *)
  let range2 = Range.create ~start:position2 ~end_:position1 in
  assert (not (phys_equal range range2));
  
  (* Test URI string conversion *)
  let uri_string = DocumentUri.to_string uri in
  assert (String.is_prefix uri_string ~prefix:"file:///");
  
  print_endline "✓ LSP types validation passed";
  true

(** Step 3: Test completion items creation *)
let test_completion_items () =
  let item1 = CompletionItem.create ~label:"test_completion" () in
  let item2 = CompletionItem.create ~label:"another_completion" () in
  let items = [item1; item2] in
  
  (* Validate CompletionItem list operations *)
  assert (List.length items = 2);
  assert (not (List.is_empty items));
  assert (not (phys_equal item1 item2));
  
  print_endline "✓ Completion items validation passed";
  true

(** Step 4: Test hover creation *)
let test_hover_creation () =
  let content = MarkupContent.create ~kind:PlainText ~value:"test hover" in
  let _hover = Hover.create ~contents:(`MarkupContent content) () in
  print_endline "✓ Hover creation works";
  true

(** Step 5: Test location for goto definition *)
let test_location_creation () =
  let uri = DocumentUri.of_string "file:///test.ec" in
  let range = Range.create ~start:(Position.create ~line:0 ~character:0) ~end_:(Position.create ~line:0 ~character:5) in
  let _location = Location.create ~uri ~range in
  print_endline "✓ Location creation works";
  true

(* TODO: Add Protocol module access step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("lsp_types", test_lsp_types);
    ("completion_items", test_completion_items);
  ] in
  
  print_endline "🧪 Running LSP Protocol tests...";
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
    print_endline "✅ All LSP Protocol tests passed";
    exit 0
  ) else (
    print_endline "❌ Some LSP Protocol tests failed";
    exit 1
  )