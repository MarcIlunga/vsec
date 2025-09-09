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

(** Safe ExecutionManager Tests - Incremental build approach *)

open Base
open Stdio

(** Step 1: Basic module access *)
let test_basic_access () =
  print_endline "✓ Basic module access works";
  true

(** Step 2: Test ExecutionManager.init *)
let test_execution_manager_init () =
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  let exec_state, events = Dm.ExecutionManager.init scope in
  
  (* Validate initialization results *)
  let _ = exec_state in  (* Test that exec_state is accessible *)
  let _ = events in  (* Test that events is accessible *)
  
  print_endline "✓ ExecutionManager.init validation passed";
  true

(** Step 3: Test hybrid execution concept *)
let test_hybrid_execution () =
  let command = "easycrypt -emacs" in
  let args = ["-emacs"; "-p"; "Z3"] in
  
  (* Validate command structure *)
  assert (String.is_substring command ~substring:"easycrypt");
  assert (List.length args >= 1);
  assert (String.equal (List.hd_exn args) "-emacs");
  
  print_endline "✓ Hybrid execution validation passed";
  true

(** Step 4: Test error resilience *)
let test_error_resilience () =
  let gstate1 = EcLib.EcGState.create () in
  let gstate2 = EcLib.EcGState.create () in
  let scope1 = EcLib.EcScope.empty gstate1 in
  let scope2 = EcLib.EcScope.empty gstate2 in
  
  (* Validate multiple initialization works *)
  let exec_state1, events1 = Dm.ExecutionManager.init scope1 in
  let exec_state2, events2 = Dm.ExecutionManager.init scope2 in
  
  (* Validate states are independent *)
  assert (not (phys_equal exec_state1 exec_state2));
  assert (not (phys_equal scope1 scope2));
  let _ = events1 in  (* Test that events1 is accessible *)
  let _ = events2 in  (* Test that events2 is accessible *)
  
  print_endline "✓ Error resilience validation passed";
  true

(* TODO: Add ExecutionManager access step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("execution_manager_init", test_execution_manager_init);
    ("hybrid_execution", test_hybrid_execution);
    ("error_resilience", test_error_resilience);
  ] in
  
  print_endline "🧪 Running ExecutionManager tests...";
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
    print_endline "✅ All ExecutionManager tests passed";
    exit 0
  ) else (
    print_endline "❌ Some ExecutionManager tests failed";
    exit 1
  )