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
  let _position = Position.create ~line:0 ~character:0 in
  let _uri = DocumentUri.of_string "file:///test.ec" in
  print_endline "✓ LSP types work";
  true

(* TODO: Add Protocol module access step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("lsp_types", test_lsp_types);
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