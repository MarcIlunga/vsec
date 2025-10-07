open Printf

(* Comprehensive Interactive Proving Test Suite *)
(* Tests all features using synchronous EasyCrypt APIs *)

let theories_paths = ref []
let init_scope = ref None

(* Setup once *)
let setup () =
  theories_paths := EcLib.EcDuneSites.Sites.theories;
  List.iter (fun theory ->
    let prelude = Filename.concat theory "prelude" in
    EcLib.EcCommands.addidir ~namespace:`System prelude;
    EcLib.EcCommands.addidir ~namespace:`System ~recursive:true theory
  ) !theories_paths;
  
  let checkmode = {
    EcLib.EcCommands.cm_checkall = false;
    cm_timeout = 5;
    cm_cpufactor = 1;
    cm_nprovers = 1;
    cm_provers = None;
    cm_profile = false;
    cm_iterate = false;
  } in
  
  init_scope := Some (EcLib.EcCommands.initial ~checkmode ~boot:false)

(* Test result tracking *)
type test_result = {
  name: string;
  passed: bool;
  error: string option;
}

let results = ref []

let add_result name passed error =
  results := { name; passed; error } :: !results

(* Execute EasyCrypt commands synchronously *)
let execute_commands init_scope commands =
  let rec exec scope = function
    | [] -> scope
    | cmd :: rest ->
        try
          let new_scope = EcLib.EcCommands.process_internal EcLib.EcCommands.loader scope cmd.EcLib.EcParsetree.gl_action in
          exec new_scope rest
        with e ->
          raise e
  in
  exec init_scope commands

(* Parse and execute text *)
let parse_and_execute init_scope text =
  let reader = EcLib.EcIo.from_string text in
  let commands = EcLib.EcIo.parseall reader in
  execute_commands init_scope commands

(* ========================================
   TEST 1: Basic Hypothesis Extraction
   ======================================== *)
let test_basic_hypotheses () =
  printf "\n📋 Test 1: Basic Hypothesis Extraction\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test1 (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Basic Hypotheses" false (Some "No goals extracted");
      printf "   ❌ FAILED: No goals extracted\n"
    | Some goals ->
      if List.length goals = 0 then (
        add_result "Basic Hypotheses" false (Some "Empty goals list");
        printf "   ❌ FAILED: Empty goals list\n"
      ) else (
        let goal = List.hd goals in
        let hyp_count = List.length goal.Protocol.ProofState.hypotheses in
        if hyp_count < 2 then (
          add_result "Basic Hypotheses" false (Some (Printf.sprintf "Expected >= 2 hypotheses, got %d" hyp_count));
          printf "   ❌ FAILED: Expected >= 2 hypotheses (H_P, H_Q), got %d\n" hyp_count
        ) else (
          let has_hp = List.exists (fun h -> String.contains h 'H' && String.contains h 'P') goal.Protocol.ProofState.hypotheses in
          let has_hq = List.exists (fun h -> String.contains h 'H' && String.contains h 'Q') goal.Protocol.ProofState.hypotheses in
          if has_hp && has_hq then (
            add_result "Basic Hypotheses" true None;
            printf "   ✅ PASSED: Found H_P and H_Q\n"
          ) else (
            add_result "Basic Hypotheses" false (Some "Missing expected hypotheses");
            printf "   ❌ FAILED: Missing H_P or H_Q\n"
          )
        )
      )
  with e ->
    add_result "Basic Hypotheses" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   TEST 2: Multiple Goals (split tactic)
   ======================================== *)
let test_multiple_goals () =
  printf "\n📋 Test 2: Multiple Goals (split tactic)\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test2 (P Q : bool): P /\\ Q => P /\\ Q.\nproof.\n  move=> [H_P H_Q].\n  split." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Multiple Goals" false (Some "No goals extracted");
      printf "   ❌ FAILED: No goals extracted\n"
    | Some goals ->
      if List.length goals < 2 then (
        add_result "Multiple Goals" false (Some (Printf.sprintf "Expected 2 goals, got %d" (List.length goals)));
        printf "   ❌ FAILED: Expected 2 goals after split, got %d\n" (List.length goals)
      ) else (
        add_result "Multiple Goals" true None;
        printf "   ✅ PASSED: Got %d goals after split\n" (List.length goals)
      )
  with e ->
    add_result "Multiple Goals" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   TEST 3: Complex Nested Hypotheses
   ======================================== *)
let test_nested_hypotheses () =
  printf "\n📋 Test 3: Complex Nested Hypotheses\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test3 (P Q R : bool): (P => Q) => P => Q /\\ R => R.\nproof.\n  move=> H1 H2 [H3 H4]." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Nested Hypotheses" false (Some "No goals extracted");
      printf "   ❌ FAILED: No goals extracted\n"
    | Some goals ->
      if List.length goals = 0 then (
        add_result "Nested Hypotheses" false (Some "Empty goals list");
        printf "   ❌ FAILED: Empty goals list\n"
      ) else (
        let goal = List.hd goals in
        let hyp_count = List.length goal.Protocol.ProofState.hypotheses in
        if hyp_count < 4 then (
          add_result "Nested Hypotheses" false (Some (Printf.sprintf "Expected >= 4 hypotheses, got %d" hyp_count));
          printf "   ❌ FAILED: Expected >= 4 hypotheses, got %d\n" hyp_count
        ) else (
          add_result "Nested Hypotheses" true None;
          printf "   ✅ PASSED: Got %d hypotheses\n" hyp_count
        )
      )
  with e ->
    add_result "Nested Hypotheses" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   TEST 4: Lemma Statement Creates Goal
   ======================================== *)
let test_lemma_goal () =
  printf "\n📋 Test 4: Lemma Statement Creates Goal\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test4 (P : bool): P => P." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Lemma Goal" false (Some "No goals after lemma statement");
      printf "   ❌ FAILED: No goals after lemma statement\n"
    | Some goals ->
      if List.length goals > 0 then (
        let goal = List.hd goals in
        if String.length goal.Protocol.ProofState.goal > 0 then (
          add_result "Lemma Goal" true None;
          printf "   ✅ PASSED: Lemma creates goal: %s\n" goal.Protocol.ProofState.goal
        ) else (
          add_result "Lemma Goal" false (Some "Empty goal text");
          printf "   ❌ FAILED: Empty goal text\n"
        )
      ) else (
        add_result "Lemma Goal" false (Some "Empty goals list");
        printf "   ❌ FAILED: Empty goals list\n"
      )
  with e ->
    add_result "Lemma Goal" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   TEST 5: Initial Goal After proof.
   ======================================== *)
let test_initial_goal () =
  printf "\n📋 Test 5: Initial Goal After 'proof.'\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test5 (P Q : bool): P => Q => P /\\ Q.\nproof." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Initial Goal" false (Some "No goals after 'proof.'");
      printf "   ❌ FAILED: No goals after 'proof.'\n"
    | Some goals ->
      if List.length goals = 0 then (
        add_result "Initial Goal" false (Some "Empty goals after 'proof.'");
        printf "   ❌ FAILED: Empty goals after 'proof.'\n"
      ) else (
        let goal = List.hd goals in
        if String.length goal.Protocol.ProofState.goal > 0 then (
          add_result "Initial Goal" true None;
          printf "   ✅ PASSED: Initial goal present: %s\n" goal.Protocol.ProofState.goal
        ) else (
          add_result "Initial Goal" false (Some "Empty goal text");
          printf "   ❌ FAILED: Empty goal text\n"
        )
      )
  with e ->
    add_result "Initial Goal" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   TEST 6: Type Variables in Hypotheses
   ======================================== *)
let test_type_variables () =
  printf "\n📋 Test 6: Type Variables in Hypotheses\n";
  try
    let scope = match !init_scope with Some s -> s | None -> failwith "Not initialized" in
    let text = "lemma test6 (P Q : bool): P => Q => P /\\ Q.\nproof.\n  move=> H_P H_Q." in
    let final_scope = parse_and_execute scope text in
    
    match Dm.EcAdapter.try_goals final_scope with
    | None ->
      add_result "Type Variables" false (Some "No goals extracted");
      printf "   ❌ FAILED: No goals extracted\n"
    | Some goals ->
      if List.length goals = 0 then (
        add_result "Type Variables" false (Some "Empty goals list");
        printf "   ❌ FAILED: Empty goals list\n"
      ) else (
        let goal = List.hd goals in
        (* Check if hypotheses include type information *)
        let has_types = List.exists (fun h -> String.contains h ':') goal.Protocol.ProofState.hypotheses in
        if has_types then (
          add_result "Type Variables" true None;
          printf "   ✅ PASSED: Hypotheses include type information\n"
        ) else (
          add_result "Type Variables" false (Some "No type information in hypotheses");
          printf "   ❌ FAILED: No type information in hypotheses\n"
        )
      )
  with e ->
    add_result "Type Variables" false (Some (Printexc.to_string e));
    printf "   ❌ FAILED: Exception: %s\n" (Printexc.to_string e)

(* ========================================
   Main Test Runner
   ======================================== *)
let () =
  printf "╔══════════════════════════════════════════════════════════╗\n";
  printf "║  COMPREHENSIVE INTERACTIVE PROVING TEST SUITE           ║\n";
  printf "╚══════════════════════════════════════════════════════════╝\n";
  
  printf "\n🔧 Setup: Configuring EasyCrypt environment...\n";
  setup ();
  printf "✅ Setup complete: %d theory paths configured\n" (List.length !theories_paths);
  
  printf "\n" ;
  printf "═══════════════════════════════════════════════════════════\n";
  printf "  RUNNING TESTS\n";
  printf "═══════════════════════════════════════════════════════════\n";
  
  test_basic_hypotheses ();
  test_multiple_goals ();
  test_nested_hypotheses ();
  test_lemma_goal ();
  test_initial_goal ();
  test_type_variables ();
  
  printf "\n";
  printf "═══════════════════════════════════════════════════════════\n";
  printf "  TEST RESULTS\n";
  printf "═══════════════════════════════════════════════════════════\n\n";
  
  let total = List.length !results in
  let passed = List.filter (fun r -> r.passed) !results |> List.length in
  let failed = total - passed in
  
  List.rev !results |> List.iter (fun r ->
    if r.passed then
      printf "  ✅ %s\n" r.name
    else
      printf "  ❌ %s%s\n" r.name 
        (match r.error with Some e -> " - " ^ e | None -> "")
  );
  
  printf "\n";
  printf "─────────────────────────────────────────────────────────\n";
  printf "  Total:  %d tests\n" total;
  printf "  Passed: %d tests (%.0f%%)\n" passed (float_of_int passed /. float_of_int total *. 100.);
  printf "  Failed: %d tests\n" failed;
  printf "─────────────────────────────────────────────────────────\n\n";
  
  if failed > 0 then (
    printf "❌ SOME TESTS FAILED\n\n";
    exit 1
  ) else (
    printf "🎉 ALL TESTS PASSED\n\n";
    exit 0
  )

