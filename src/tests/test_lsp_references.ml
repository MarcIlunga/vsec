(**************************************************************************)
(* References Tests (text-level occurrences guiding provider behavior) *)

open Base
open Stdio

let print_ok msg = print_endline msg; true

let sample_text = String.concat ~sep:"\n" [
  "theory T.";
  "lemma foo: true.";
  "proof.";
  "  trivial.";
  "qed.";
  "print foo.";
  "apply foo.";
  "end T.";
]

let positions_of_symbol text sym =
  let lines = String.split ~on:'\n' text in
  List.filter_mapi lines ~f:(fun i line ->
    match String.substr_index line ~pattern:sym with
    | None -> None
    | Some col -> Some (i, col)
  )

let test_references_count () =
  let refs = positions_of_symbol sample_text "foo" in
  (* Expect at least definition + two uses *)
  assert (List.length refs >= 3);
  print_ok "✓ References count (text-level) passed"

let test_references_positions () =
  let refs = positions_of_symbol sample_text "foo" in
  (* Expected lines (0-based): definition line=1, prints line=5, apply line=6 *)
  let lines = List.map refs ~f:fst |> Set.of_list (module Int) in
  assert (Set.mem lines 1);
  assert (Set.mem lines 5);
  assert (Set.mem lines 6);
  print_ok "✓ References positions (text-level) passed"

let run_tests () =
  let tests = [
    ("references_count", test_references_count);
    ("references_positions", test_references_positions);
  ] in
  print_endline "🧪 Running References tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All References tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some References tests failed"; Stdlib.exit 1)


