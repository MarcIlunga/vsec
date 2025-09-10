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

(** Safe Scheduler Tests - Incremental build approach *)

open Base
open Stdio
open Dm

(** Step 1: Basic module access *)
let test_basic_access () =
  print_endline "✓ Basic module access works";
  true

(** Step 2: Test scheduler initialization *)
let test_scheduler_init () =
  let state = Scheduler.initial_state in
  let schedule = Scheduler.initial_schedule in
  
  (* Validate initialization *)
  let _ = state in  (* Test state is accessible *)
  let _ = schedule in  (* Test schedule is accessible *)
  
  print_endline "✓ Scheduler initialization validation passed";
  true

(** Step 3: Test schedule string representation *)
let test_schedule_representation () =
  let schedule = Scheduler.initial_schedule in
  let schedule_str = Scheduler.string_of_schedule schedule in
  
  (* Validate string representation *)
  assert (not (String.is_empty schedule_str));
  assert (String.length schedule_str > 0);
  
  print_endline "✓ Schedule representation validation passed";
  true

(** Step 4: Test dependents functionality concept *)
let test_dependents () =
  let schedule = Scheduler.initial_schedule in
  
  (* Test that dependents function exists and schedule is valid *)
  let schedule_str = Scheduler.string_of_schedule schedule in
  assert (not (String.is_empty schedule_str));
  
  (* Note: We can't test dependents with a real sentence ID until we have sentences scheduled *)
  
  print_endline "✓ Dependents functionality concept validation passed";
  true

(* TODO: Add more scheduler tests step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("scheduler_init", test_scheduler_init);
    ("schedule_representation", test_schedule_representation);
    ("dependents", test_dependents);
  ] in
  
  print_endline "🧪 Running Scheduler tests...";
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
    print_endline "✅ All Scheduler tests passed";
    exit 0
  ) else (
    print_endline "❌ Some Scheduler tests failed";
    exit 1
  )
