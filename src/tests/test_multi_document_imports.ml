(**************************************************************************)
(* Multi-document imports extraction test *)

open Base
open Stdio
open Dm

let print_ok msg = print_endline msg; true

let text = String.concat ~sep:"\n" [
  "require import AllCore.";
  "import MyLib.";
  "theory T.";
  "end T.";
]

let test_imports_extract () =
  let g = EcLib.EcGState.create () in
  let init_scope = EcLib.EcScope.empty g in
  let doc = Document.create_document init_scope text in
  let imps = Document.imports doc in
  assert (List.mem imps "AllCore" ~equal:String.equal);
  assert (List.mem imps "MyLib" ~equal:String.equal);
  print_ok "✓ Multi-document imports extracted"

let run_tests () =
  let tests = [ ("imports_extract", test_imports_extract) ] in
  print_endline "🧪 Running Multi-Document Imports tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All Multi-Document Imports tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some Multi-Document Imports tests failed"; Stdlib.exit 1)


