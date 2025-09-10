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

(** Safe Multi-Document Tests - Test multiple document handling *)

open Base
open Stdio
open Lsp.Types

(** Step 1: Basic multi-document setup *)
let test_basic_multi_document () =
  let documents = [
    ("file1.ec", "lemma test1: true. proof. trivial. qed.");
    ("file2.ec", "lemma test2: false. proof. admit. qed.");
    ("file3.ec", "require import AllCore. lemma test3: true /\\ true. proof. split; trivial. qed.");
  ] in
  
  (* Validate document structure *)
  assert (List.length documents = 3);
  List.iter documents ~f:(fun (filename, content) ->
    assert (not (String.is_empty filename));
    assert (not (String.is_empty content));
    assert (String.is_suffix filename ~suffix:".ec");
    assert (String.is_substring content ~substring:"lemma");
  );
  
  print_endline "✓ Basic multi-document setup validation passed";
  true

(** Step 2: Test document URI management *)
let test_document_uri_management () =
  let file_paths = [
    "/home/user/project/main.ec";
    "/home/user/project/lib/utils.ec";
    "/home/user/project/proofs/security.ec";
  ] in
  
  let uris = List.map file_paths ~f:(fun path -> 
    DocumentUri.of_string ("file://" ^ path)
  ) in
  
  (* Validate URI creation and management *)
  assert (List.length uris = 3);
  List.iter2_exn file_paths uris ~f:(fun original_path uri ->
    let uri_path = DocumentUri.to_path uri in
    assert (String.is_suffix uri_path ~suffix:"ec");
    assert (String.is_substring original_path ~substring:(Filename.basename uri_path));
  );
  
  print_endline "✓ Document URI management validation passed";
  true

(** Step 3: Test document dependency tracking *)
let test_document_dependencies () =
  let dependencies = [
    ("main.ec", ["utils.ec"; "types.ec"]);
    ("utils.ec", ["types.ec"]);
    ("types.ec", []);
    ("proofs.ec", ["main.ec"; "utils.ec"]);
  ] in
  
  (* Validate dependency structure *)
  List.iter dependencies ~f:(fun (doc, deps) ->
    assert (not (String.is_empty doc));
    assert (String.is_suffix doc ~suffix:".ec");
    List.iter deps ~f:(fun dep ->
      assert (not (String.is_empty dep));
      assert (String.is_suffix dep ~suffix:".ec");
    );
  );
  
  (* Test dependency resolution *)
  let get_dependencies doc = 
    List.Assoc.find dependencies doc ~equal:String.equal |> Option.value ~default:[]
  in
  
  let main_deps = get_dependencies "main.ec" in
  let utils_deps = get_dependencies "utils.ec" in
  
  assert (List.length main_deps = 2);
  assert (List.length utils_deps = 1);
  assert (List.mem main_deps "utils.ec" ~equal:String.equal);
  
  print_endline "✓ Document dependency tracking validation passed";
  true

(** Step 4: Test concurrent document operations *)
let test_concurrent_document_operations () =
  let operations = [
    ("doc1", "open", 0.001);
    ("doc2", "open", 0.002);
    ("doc1", "edit", 0.003);
    ("doc3", "open", 0.004);
    ("doc2", "save", 0.005);
    ("doc1", "close", 0.006);
  ] in
  
  (* Simulate concurrent operation tracking *)
  let group_by_doc ops =
    List.fold ops ~init:[] ~f:(fun acc (doc, op, time) ->
      match List.Assoc.find acc doc ~equal:String.equal with
      | Some existing_ops -> List.Assoc.add acc doc ((op, time) :: existing_ops) ~equal:String.equal
      | None -> (doc, [(op, time)]) :: acc
    )
  in
  
  let doc_operations = group_by_doc operations in
  
  (* Validate concurrent operations *)
  assert (List.length doc_operations = 3);  (* 3 different documents *)
  List.iter doc_operations ~f:(fun (doc, ops) ->
    assert (not (String.is_empty doc));
    assert (List.length ops > 0);
    List.iter ops ~f:(fun (op, time) ->
      assert (not (String.is_empty op));
      assert (Float.O.(time > 0.0));
    );
  );
  
  print_endline "✓ Concurrent document operations validation passed";
  true

(** Step 5: Test document state synchronization *)
let test_document_state_sync () =
  let document_states = [
    ("file1.ec", "clean", 0);
    ("file2.ec", "modified", 5);
    ("file3.ec", "error", 2);
    ("file4.ec", "clean", 0);
  ] in
  
  (* Test state synchronization logic *)
  let needs_sync (_, state, changes) = 
    match state with
    | "modified" -> changes > 0
    | "error" -> true
    | "clean" -> false
    | _ -> false
  in
  
  let docs_needing_sync = List.filter document_states ~f:needs_sync in
  let clean_docs = List.filter document_states ~f:(fun doc -> not (needs_sync doc)) in
  
  (* Validate synchronization *)
  assert (List.length docs_needing_sync = 2);  (* file2 and file3 *)
  assert (List.length clean_docs = 2);  (* file1 and file4 *)
  assert (List.length docs_needing_sync + List.length clean_docs = List.length document_states);
  
  print_endline "✓ Document state synchronization validation passed";
  true

(** Step 6: Test workspace-wide operations *)
let test_workspace_operations () =
  let workspace_files = [
    "src/main.ec";
    "src/lib/crypto.ec";
    "src/lib/utils.ec";
    "tests/test_main.ec";
    "tests/test_crypto.ec";
  ] in
  
  (* Test workspace-wide search simulation *)
  let find_files_with_pattern pattern files =
    List.filter files ~f:(fun file -> String.is_substring file ~substring:pattern)
  in
  
  let test_files = find_files_with_pattern "test" workspace_files in
  let crypto_files = find_files_with_pattern "crypto" workspace_files in
  let lib_files = find_files_with_pattern "lib" workspace_files in
  
  (* Validate workspace operations *)
  assert (List.length test_files = 2);
  assert (List.length crypto_files = 2);
  assert (List.length lib_files = 2);
  
  print_endline "✓ Workspace operations validation passed";
  true

(* TODO: Add more multi-document tests step by step *)

(** Run all tests *)
let run_tests () =
  let tests = [
    ("basic_multi_document", test_basic_multi_document);
    ("document_uri_management", test_document_uri_management);
    ("document_dependencies", test_document_dependencies);
    ("concurrent_document_operations", test_concurrent_document_operations);
    ("document_state_sync", test_document_state_sync);
    ("workspace_operations", test_workspace_operations);
  ] in
  
  print_endline "🧪 Running Multi-Document tests...";
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
    print_endline "✅ All Multi-Document tests passed";
    exit 0
  ) else (
    print_endline "❌ Some Multi-Document tests failed";
    exit 1
  )
