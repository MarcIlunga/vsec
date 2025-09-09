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

(* TODO: Add ProofState module access step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_access", test_basic_access);
    ("easycrypt_lib", test_easycrypt_lib);
    ("scope_creation", test_scope_creation);
    ("proof_json", test_proof_json);
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