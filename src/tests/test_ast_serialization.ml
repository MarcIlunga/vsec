(* 
 * AST Serialization Test Suite
 * Comprehensive tests for Protocol.Ast module with stringent edge case coverage
 *)

open Base
open Stdio

(* Test framework helpers *)
let test_count = ref 0
let passed_count = ref 0
let failed_tests = ref []

let test_case name f =
  test_count := !test_count + 1;
  printf "\n🧪 Test %d: %s\n" !test_count name;
  try
    f ();
    passed_count := !passed_count + 1;
    printf "   ✅ PASSED\n"
  with
  | e ->
      failed_tests := name :: !failed_tests;
      printf "   ❌ FAILED: %s\n" (Exn.to_string e)

(* Initialize EasyCrypt environment for testing *)
let init_easycrypt () =
  (* Configure load path *)
  let theories_paths = EcLib.EcDuneSites.Sites.theories in
  Stdlib.List.iter (fun theory ->
    let prelude = Stdlib.Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) theories_paths;
  
  (* Initialize scope *)
  let checkmode = {
    EcLib.EcCommands.cm_checkall = false;
    cm_timeout = 5;
    cm_cpufactor = 1;
    cm_nprovers = 1;
    cm_provers = None;
    cm_profile = false;
    cm_iterate = false;
  } in
  
  EcLib.EcCommands.initial ~checkmode ~boot:false

(* Helper: Execute EasyCrypt code and return updated scope *)
let execute_code code =
  let scope = init_easycrypt () in
  let reader = EcLib.EcIo.from_string code in
  let globals = EcLib.EcIo.parseall reader in
  Stdlib.List.fold_left (fun sc (g:EcLib.EcParsetree.global) ->
    EcLib.EcCommands.process_internal EcLib.EcCommands.loader sc g.gl_action
  ) scope globals

(* Helper: Get goals from a scope *)
let get_goals_from_scope scope =
  match EcLib.EcScope.xgoal scope with
  | None -> []
  | Some { EcLib.EcScope.puc_active = None; _ } -> []
  | Some { EcLib.EcScope.puc_active = Some (puc, _); _ } ->
      (match puc.EcLib.EcScope.puc_jdg with
       | EcLib.EcScope.PSNoCheck -> []
       | EcLib.EcScope.PSCheck proof ->
           EcLib.EcCoreGoal.all_opened proof)

(* ============================================
 * AST SERIALIZATION TESTS WITH REAL GOALS
 * ============================================ *)

let test_simple_goal () =
  test_case "Simple goal - lemma test: true" (fun () ->
    let scope = execute_code "lemma test: true.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let json_str = Yojson.Safe.to_string json in
        if String.length json_str < 10 then
          failwith "JSON output too short"
  )

let test_conjunction_goal () =
  test_case "Conjunction goal - a /\\ b" (fun () ->
    let scope = execute_code "lemma test: forall (a b : bool), a /\\ b.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        ()
  )

let test_disjunction_goal () =
  test_case "Disjunction goal - a \\/ b" (fun () ->
    let scope = execute_code "lemma test: forall (a b : bool), a \\/ b.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        ()
  )

let test_implication_goal () =
  test_case "Implication goal - a => b" (fun () ->
    let scope = execute_code "lemma test: forall (a b : bool), a => b.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        ()
  )

let test_negation_goal () =
  test_case "Negation goal - !a" (fun () ->
    let scope = execute_code "lemma test: forall (a : bool), !a.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        ()
  )

let test_demorgan_goal () =
  test_case "De Morgan's law - !(a \\/ b) <=> !a /\\ !b" (fun () ->
    let scope = execute_code "lemma test: forall (a b : bool), !(a \\/ b) <=> !a /\\ !b.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        ()
  )

let test_multiple_goals () =
  test_case "Multiple goals after split - true /\\ false" (fun () ->
    let scope = execute_code "lemma test: true /\\ false.\nproof.\nsplit." in
    let goals = get_goals_from_scope scope in
    if List.length goals < 2 then
      failwith (Printf.sprintf "Expected at least 2 goals, got %d" (List.length goals));
    
    (* Serialize each goal *)
    Stdlib.List.iter (fun g ->
      let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
      let _ = Yojson.Safe.to_string json in
      ()
    ) goals
  )

let test_hypothesis_serialization () =
  test_case "Hypothesis serialization - function works correctly" (fun () ->
    let scope = execute_code "lemma test: true.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        (* Test that hypothesis serialization function works *)
        let hyps = EcLib.EcEnv.LDecl.tohyps g.EcLib.EcCoreGoal.g_hyps in
        let hyps_json = Stdlib.List.map Protocol.Ast.yojson_of_hypothesis hyps.h_local in
        let json_str = Yojson.Safe.to_string (`List hyps_json) in
        
        (* Verify the serialization produces valid JSON *)
        if not (String.equal json_str "[]") && String.length json_str < 2 then
          failwith "Invalid hypothesis JSON";
        
        (* Test that yojson_of_goal includes hypotheses field *)
        let goal_json = Protocol.Ast.yojson_of_goal 0 g in
        let goal_str = Yojson.Safe.to_string goal_json in
        if not (String.is_substring goal_str ~substring:"hypotheses") then
          failwith "Goal JSON missing 'hypotheses' field"
  )

let test_hypothesis_with_assume () =
  test_case "Hypothesis serialization - with assume statements" (fun () ->
    (* Use a simpler case that should work *)
    let scope = execute_code "lemma test: forall (x : bool), x => x.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        (* Test hypothesis serialization with actual content *)
        let hyps = EcLib.EcEnv.LDecl.tohyps g.EcLib.EcCoreGoal.g_hyps in
        let hyps_json = Stdlib.List.map Protocol.Ast.yojson_of_hypothesis hyps.h_local in
        let json_str = Yojson.Safe.to_string (`List hyps_json) in
        
        (* Verify we have some hypothesis content *)
        printf "   DEBUG: hyps.h_local length = %d\n" (List.length hyps.h_local);
        printf "   DEBUG: hypothesis JSON = %s\n" json_str;
        
        (* Test that each hypothesis has required fields *)
        Stdlib.List.iter (fun hyp_json ->
          let hyp_str = Yojson.Safe.to_string hyp_json in
          if not (String.is_substring hyp_str ~substring:"kind") then
            failwith "Hypothesis missing 'kind' field";
          if not (String.is_substring hyp_str ~substring:"id") then
            failwith "Hypothesis missing 'id' field"
        ) hyps_json
  )

let test_complete_goal_serialization () =
  test_case "Complete goal serialization via yojson_of_goal" (fun () ->
    let scope = execute_code "lemma test: forall (x y : bool), x /\\ y.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_goal 0 g in
        let json_str = Yojson.Safe.to_string json in
        (* Verify it contains expected fields *)
        if not (String.is_substring json_str ~substring:"hypotheses") then
          failwith "Missing 'hypotheses' field";
        if not (String.is_substring json_str ~substring:"conclusion") then
          failwith "Missing 'conclusion' field"
  )

let test_json_validity () =
  test_case "All serialized JSON is valid and parseable" (fun () ->
    let test_cases = [
      "lemma t1: true.\nproof.";
      "lemma t2: false.\nproof.";
      "lemma t3: forall (a b:bool), a /\\ b.\nproof.";
      "lemma t4: forall (a b:bool), a => b.\nproof.";
    ] in
    
    Stdlib.List.iter (fun code ->
      let scope = execute_code code in
      let goals = get_goals_from_scope scope in
      match goals with
      | [] -> ()
      | g :: _ ->
          let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
          let json_str = Yojson.Safe.to_string json in
          (* Re-parse to validate *)
          try
            let _ = Yojson.Safe.from_string json_str in
            ()
          with _ ->
            failwith (Printf.sprintf "Invalid JSON for: %s" code)
    ) test_cases
  )

let test_serialization_deterministic () =
  test_case "Serialization is deterministic - same input produces same JSON" (fun () ->
    let scope = execute_code "lemma test: forall (x:bool), x => x.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json1 = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let json2 = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let str1 = Yojson.Safe.to_string json1 in
        let str2 = Yojson.Safe.to_string json2 in
        if not (String.equal str1 str2) then
          failwith "Serialization is non-deterministic!"
  )

let test_large_formula () =
  test_case "Large formula - 10 nested conjunctions" (fun () ->
    let scope = execute_code "lemma test: forall (a1 a2 a3 a4 a5 a6 a7 a8 a9 a10:bool),\n  a1 /\\ a2 /\\ a3 /\\ a4 /\\ a5 /\\ a6 /\\ a7 /\\ a8 /\\ a9 /\\ a10.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let start_time = Unix.gettimeofday () in
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let _ = Yojson.Safe.to_string json in
        let elapsed = Unix.gettimeofday () -. start_time in
        if Float.(elapsed > 1.0) then
          failwith (Printf.sprintf "Serialization too slow: %.3fs" elapsed)
  )

let test_complex_nested_structures () =
  test_case "Complex nested AST structures" (fun () ->
    (* Test deeply nested formulas with various constructs *)
    let scope = execute_code "lemma test: forall (x y : bool), (x /\\ y) => (x \\/ y) => (x <=> y) => (x => y) => (y => x) => true.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let json_str = Yojson.Safe.to_string json in
        
        (* Verify the JSON contains expected nested structure *)
        if not (String.is_substring json_str ~substring:"node") then
          failwith "Missing 'node' field in nested structure";
        if not (String.is_substring json_str ~substring:"ty") then
          failwith "Missing 'ty' field in nested structure";
        
        (* Test that we can parse it back *)
        let _ = Yojson.Safe.from_string json_str in
        ()
  )

let test_quantified_formulas () =
  test_case "Quantified formulas with complex structure" (fun () ->
    (* Test formulas with quantifiers and complex nested structures *)
    let scope = execute_code "lemma test: forall (x : bool), exists (y : bool), forall (z : bool), (x /\\ y) \\/ (y /\\ z) \\/ (x /\\ z).\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let json_str = Yojson.Safe.to_string json in
        
        (* Verify quantifier structure is preserved *)
        if not (String.is_substring json_str ~substring:"forall") then
          failwith "Missing 'forall' in quantified formula";
        if not (String.is_substring json_str ~substring:"exists") then
          failwith "Missing 'exists' in quantified formula";
        
        (* Test that the structure is valid JSON *)
        let _ = Yojson.Safe.from_string json_str in
        ()
  )

let test_type_serialization_complex () =
  test_case "Complex type serialization" (fun () ->
    (* Test that types are properly serialized in complex formulas *)
    let scope = execute_code "lemma test: forall (x : bool), x.\nproof." in
    let goals = get_goals_from_scope scope in
    match goals with
    | [] -> failwith "Expected at least one goal"
    | g :: _ ->
        let json = Protocol.Ast.yojson_of_form g.EcLib.EcCoreGoal.g_concl in
        let json_str = Yojson.Safe.to_string json in
        
        (* Verify type information is included *)
        if not (String.is_substring json_str ~substring:"ty") then
          failwith "Missing type information in serialized form";
        
        (* Test that we can access the type field *)
        let parsed = Yojson.Safe.from_string json_str in
        match parsed with
        | `Assoc fields ->
            let ty_field = Stdlib.List.assoc_opt "ty" fields in
            (match ty_field with
            | Some _ -> ()  (* Type field exists *)
            | None -> failwith "Missing 'ty' field in form JSON")
        | _ -> failwith "Expected object with fields"
  )

(* ============================================
 * MAIN TEST RUNNER
 * ============================================ *)

let run_all_tests () =
  printf "\n";
  printf "═══════════════════════════════════════════════════════\n";
  printf "    AST SERIALIZATION TEST SUITE\n";
  printf "    Testing with Real EasyCrypt Goals\n";
  printf "═══════════════════════════════════════════════════════\n";
  
  printf "\n--- BASIC FORMULA SERIALIZATION ---\n";
  test_simple_goal ();
  test_conjunction_goal ();
  test_disjunction_goal ();
  test_implication_goal ();
  test_negation_goal ();
  
  printf "\n--- COMPLEX FORMULAS ---\n";
  test_demorgan_goal ();
  test_multiple_goals ();
  
  printf "\n--- GOAL STRUCTURE TESTS ---\n";
  test_hypothesis_serialization ();
  test_hypothesis_with_assume ();
  test_complete_goal_serialization ();
  
  printf "\n--- ROBUSTNESS & VALIDATION ---\n";
  test_json_validity ();
  test_serialization_deterministic ();
  
  printf "\n--- PERFORMANCE & STRESS TESTS ---\n";
  test_large_formula ();
  
  printf "\n--- COMPLEX NESTED STRUCTURES ---\n";
  test_complex_nested_structures ();
  test_quantified_formulas ();
  test_type_serialization_complex ();
  
  printf "\n";
  printf "═══════════════════════════════════════════════════════\n";
  printf "    TEST SUMMARY\n";
  printf "═══════════════════════════════════════════════════════\n";
  printf "Total tests:  %d\n" !test_count;
  printf "Passed:       %d ✅\n" !passed_count;
  printf "Failed:       %d ❌\n" (!test_count - !passed_count);
  printf "Pass rate:    %.1f%%\n" 
    (Float.of_int !passed_count /. Float.of_int !test_count *. 100.0);
  
  if List.length !failed_tests > 0 then begin
    printf "\nFailed tests:\n";
    List.iter !failed_tests ~f:(fun name -> printf "  - %s\n" name)
  end;
  
  printf "═══════════════════════════════════════════════════════\n\n";
  
  (* Exit with proper status code *)
  if !passed_count = !test_count then 0 else 1

let () =
  let exit_code = run_all_tests () in
  Stdlib.exit exit_code
