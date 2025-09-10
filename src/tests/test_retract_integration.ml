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
  let rec loop st = function
    | [] -> st
    | e::es ->
      match Sel.Event.get e with
      | DocumentManager.DocumentEvent ev ->
        let doc, new_events, parsing_end = Document.handle_event (DocumentManager.Internal.document st) ev in
        let st = { st with DocumentManager.document = doc } in
        let st = match parsing_end with
          | None -> st
          | Some info -> fst (DocumentManager.Internal.validate_document st info)
        in
        loop st (DocumentManager.Internal.inject_doc_events new_events @ es)
      | _ -> loop st es
  in
  loop st events

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
    let st = { st with DocumentManager.observe_id = DocumentManager.Id last.Document.id } in
    let st', _events = DocumentManager.interpret_to_previous st in
    begin match prev_opt, DocumentManager.Internal.observe_id st' with
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


