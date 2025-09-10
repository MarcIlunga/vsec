(**************************************************************************)
(* Go-to Definition Tests (outline/env-based) *)

open Base
open Stdio
open Lsp.Types
open Dm
open Sel

let print_ok msg = print_endline msg; true

let sample_text = String.concat ~sep:"\n" [
  "theory T.";
  "lemma foo: true.";
  "proof.";
  "  trivial.";
  "qed.";
  "print foo.";
  "end T.";
]

let init_state () =
  let g = EcLib.EcGState.create () in
  EcLib.EcScope.empty g

let test_outline_jump () =
  let vst = init_state () in
  let uri = DocumentUri.of_string "file:///test.ec" in
  let st, events = DocumentManager.init vst uri ~text:sample_text in
  (* For testing, we'll just use the initial state and ignore events *)
  (* Real event processing happens in the main LSP loop *)
  let st = st in
  (* Position on the "print foo." line at "foo" start *)
  let raw = Document.raw_document (DocumentManager.Internal.document st) in
  let pos = Position.create ~line:5 ~character:6 in
  match DocumentManager.jump_to_definition st pos with
  | None -> false
  | Some (range, name) ->
    assert (String.equal name "foo");
    (* definition should be at line 1 (0-based), near column 6 *)
    assert (range.start.line = 1);
    print_ok "✓ Go-to definition located outline symbol"

let run_tests () =
  let tests = [ ("outline_jump", test_outline_jump) ] in
  print_endline "🧪 Running Go-to Definition tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All Go-to Definition tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some Go-to Definition tests failed"; Stdlib.exit 1)


