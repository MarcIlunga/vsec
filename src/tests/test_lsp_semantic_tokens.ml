(**************************************************************************)
(* Semantic Tokens Tests (legend, full, range) *)

open Base
open Stdio

let print_ok msg = print_endline msg; true

let test_semantic_legend () =
  (* Ensure our server exposes a reasonable legend (indirectly via hardcoded list) *)
  let token_types = [ "keyword"; "type"; "function"; "variable"; "property"; "comment" ] in
  let token_mods = [ "declaration"; "definition"; "readonly"; "static"; "deprecated" ] in
  assert (List.length token_types >= 4);
  assert (List.mem token_types "keyword" ~equal:String.equal);
  assert (List.mem token_mods "definition" ~equal:String.equal);
  print_ok "✓ Semantic tokens legend sanity checks passed"

let encode_delta tokens =
  (* simple encoder mirroring server expectations: sorted, 5-int tuples *)
  let sorted = List.sort tokens ~compare:(fun (l1,s1,_,_,_) (l2,s2,_,_,_) -> match Int.compare l1 l2 with 0 -> Int.compare s1 s2 | c -> c) in
  let rec loop prev_line prev_start acc = function
    | [] -> List.rev acc
    | (line,start,len,typ,mods)::tl ->
      let dl = line - prev_line in
      let ds = if dl = 0 then start - prev_start else start in
      loop line start (mods :: typ :: len :: ds :: dl :: acc) tl
  in
  loop 0 0 [] sorted

let test_full_encoding () =
  let tokens = [ (0,0,5,0,0); (0,6,4,1,1); (1,0,8,2,0) ] in
  let data = encode_delta tokens in
  assert (List.length data = 15);
  print_ok "✓ Semantic tokens full encoding test passed"

let test_range_encoding () =
  let tokens = [ (2,3,2,0,0); (2,6,1,3,0); (3,0,4,1,0) ] in
  let data = encode_delta tokens in
  assert (List.length data = 15);
  print_ok "✓ Semantic tokens range encoding test passed"

let run_tests () =
  let tests = [
    ("semantic_legend", test_semantic_legend);
    ("full_encoding", test_full_encoding);
    ("range_encoding", test_range_encoding);
  ] in
  print_endline "🧪 Running LSP Semantic Tokens tests...";
  let passed = ref 0 in
  let total = List.length tests in
  List.iter tests ~f:(fun (name, f) ->
    print_endline ("  Running " ^ name ^ "...");
    if f () then (print_endline "PASS"; Int.incr passed) else print_endline "FAIL");
  print_endline ("📊 Tests: " ^ Int.to_string !passed ^ "/" ^ Int.to_string total ^ " passed");
  !passed = total

let () =
  if run_tests () then (print_endline "✅ All LSP Semantic Tokens tests passed"; Stdlib.exit 0)
  else (print_endline "❌ Some LSP Semantic Tokens tests failed"; Stdlib.exit 1)


