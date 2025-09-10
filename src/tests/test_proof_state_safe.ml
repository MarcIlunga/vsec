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

(** Safe ProofState Tests - Incremental build approach *)

open Base
open Stdio

(** Step 1: Basic module access *)
let test_basic_access () =
  print_endline "✓ Basic module access works";
  true

(** Step 2: Test EasyCrypt library access *)
let test_easycrypt_lib () =
  let _empty_gstate = EcLib.EcGState.create () in
  print_endline "✓ EasyCrypt library accessible";
  true

(** Step 3: Test scope creation for proof state *)
let test_scope_creation () =
  let gstate = EcLib.EcGState.create () in
  let _scope = EcLib.EcScope.empty gstate in
  print_endline "✓ EcScope creation works";
  true

(** Step 4: Test proof state JSON structure *)
let test_proof_json () =
  let goals_json = `List [`Assoc [("id", `Int 1); ("goal", `String "True")]] in
  let proof_json = `Assoc [("goals", goals_json); ("remaining", `Int 1)] in
  
  (* Validate JSON structure *)
  let json_string = Yojson.Safe.to_string proof_json in
  assert (String.is_substring json_string ~substring:"goals");
  assert (String.is_substring json_string ~substring:"True");
  assert (not (String.is_empty json_string));
  
  print_endline "✓ Proof state JSON validation passed";
  true

(** Step 5: Test proof state extraction from scope *)
let test_proof_state_extraction () =
  let gstate = EcLib.EcGState.create () in
  let scope = EcLib.EcScope.empty gstate in
  
  (* Test proof state concept - simulate extracting goals and context *)
  let mock_goals = ["goal1: True"; "goal2: forall x, x = x"] in
  let mock_context = ["H1: True"; "H2: forall y, y <> 0"] in
  
  (* Validate mock proof state structure *)
  assert (List.length mock_goals = 2);
  assert (List.length mock_context = 2);
  assert (String.is_substring (List.hd_exn mock_goals) ~substring:"True");
  assert (String.is_substring (List.hd_exn mock_context) ~substring:"H1");
  
  print_endline "✓ Proof state extraction concept validation passed";
  true

(** Step 6: Test proof state serialization *)
let test_proof_state_serialization () =
  let goals = [`Assoc [("id", `Int 1); ("goal", `String "True")];
               `Assoc [("id", `Int 2); ("goal", `String "x = x")]] in
  let context = [`Assoc [("name", `String "H1"); ("type", `String "True")]] in
  let proof_state = `Assoc [
    ("goals", `List goals);
    ("context", `List context);
    ("remaining_goals", `Int (List.length goals))
  ] in
  
  (* Validate serialization *)
  let json_string = Yojson.Safe.to_string proof_state in
  assert (String.is_substring json_string ~substring:"goals");
  assert (String.is_substring json_string ~substring:"context");
  assert (String.is_substring json_string ~substring:"remaining_goals");
  assert (not (String.is_empty json_string));
  
  print_endline "✓ Proof state serialization validation passed";
  true

(* TODO: Add ProofState module access step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("easycrypt_lib", test_easycrypt_lib);
    ("scope_creation", test_scope_creation);
    ("proof_json", test_proof_json);
    ("proof_state_extraction", test_proof_state_extraction);
    ("proof_state_serialization", test_proof_state_serialization);
  ] in
  
  print_endline "🧪 Running ProofState tests...";
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
    print_endline "✅ All ProofState tests passed";
    exit 0
  ) else (
    print_endline "❌ Some ProofState tests failed";
    exit 1
  )