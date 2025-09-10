(**************************************************************************)
(* Syntax Highlighting Classification Tests *)

open Base
open Stdio
open Dm

let print_ok msg = print_endline msg; true

let test_keyword_classification () =
  let open Types.EasyCryptClassification in
  let cases = [
    ("lemma foo.", EcDefinition);
    ("theorem bar.", EcDefinition);
    ("proof.", EcProofStep);
    ("qed.", EcProofStep);
    ("module M.", EcModule);
    ("theory T.", EcModule);
    ("print foo.", EcQuery);
  ] in
  List.iter cases ~f:(fun (s, expected) ->
    let got = Types.EasyCryptClassification.classify_string s in
    assert (phys_equal got expected)
  );
  print_ok "✓ Keyword classification passed"

let test_mixed_lines () =
  let lines = [
    "lemma f.", Types.EasyCryptClassification.EcDefinition;
    "apply H.", Types.EasyCryptClassification.EcProofStep;
    "check f.", Types.EasyCryptClassification.EcQuery;
  ] in
  List.iter lines ~f:(fun (s, expected) ->
    let got = Types.EasyCryptClassification.classify_string s in
    assert (phys_equal got expected)
  );
  print_ok "✓ Mixed lines classification passed"

let run_tests () =
  let tests = [
    ("keyword_classification", test_keyword_classification);
    ("mixed_lines", test_mixed_lines);
  ] in
  print_endline "🧪 Running Syntax Highlighting tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All Syntax Highlighting tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some Syntax Highlighting tests failed"; Stdlib.exit 1)


