(**************************************************************************)
(* Retract/Reset Integration Test *)

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

let drain_parse st events =
  (* For testing, we'll just return the initial state and ignore events *)
  (* Real event processing happens in the main LSP loop *)
  st

let test_retract_to_previous () =
  let vst = init_state () in
  let uri = DocumentUri.of_string "file:///test.ec" in
  let st, events = DocumentManager.init vst uri ~text:sample_text in
  let st = drain_parse st events in
  match Document.get_last_sentence (DocumentManager.Internal.document st) with
  | None -> false
  | Some last ->
    let prev_opt =
      match Document.find_sentence_before (DocumentManager.Internal.document st) last.start with
      | None -> None
      | Some p -> Some p.Document.id
    in
    (* Test the retract functionality by navigating to the last sentence first *)
    let st', _events = DocumentManager.interpret_to_end st in
    let st'', _events = DocumentManager.interpret_to_previous st' in
    begin match prev_opt, DocumentManager.Internal.observe_id st'' with
    | Some pid, Some oid -> assert (pid = oid); print_ok "✓ Retract moved to previous sentence"
    | None, None -> print_ok "✓ Retract at top becomes Top"
    | _ -> false
    end

let run_tests () =
  let tests = [ ("retract_to_previous", test_retract_to_previous) ] in
  print_endline "🧪 Running Retract integration tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All Retract integration tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some Retract integration tests failed"; Stdlib.exit 1)


